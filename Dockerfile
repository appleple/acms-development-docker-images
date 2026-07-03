# syntax=docker/dockerfile:1

# ビルドするPHPバージョンは docker-bake.hcl / CI のマトリクスから渡す。
# ローカルで単体ビルドする場合は --build-arg PHP_VERSION=8.3 を指定する。
ARG PHP_VERSION=8.3
FROM php:${PHP_VERSION}-apache

# pecl 拡張の既定バージョン（新しめの PHP 用。再現性のため固定）。
# 古い PHP では下の RUN 内で対応する旧版へ自動的に切り替える。
ARG APCU_VERSION=5.1.28
ARG REDIS_VERSION=6.3.0
ARG IMAGICK_VERSION=3.8.1
ARG XDEBUG_VERSION=3.5.3
ARG PCOV_VERSION=1.0.12

# ---- OS パッケージ & PHP 拡張 ----
# xdebug/pcov は常時インストールしておき、有効化は実行時に行う。
#  - xdebug: XDEBUG=true のときだけ entrypoint が有効化（-xdebug 専用イメージ不要）
#  - pcov:   既定は pcov.enabled=0（カバレッジ取得時のみ -d pcov.enabled=1）
# OPcache は PHP 8.5 で静的組込みのため install せず、未ロード時のみ enable する。
# PHP 7.x 対応のため、apt ソース(archive)・gd フラグ・redis/xdebug の版を分岐する。
#
# ビルドにしか使わないパッケージ（build-essential・*-dev ヘッダ）は最後に
# apt-mark で洗い出して purge し、開発用途で使う CLI（git・ssh・python 等）と
# 拡張が実行時にリンクする共有ライブラリだけを残す。
RUN set -eux; \
    PHP_ID="$(php -r 'echo PHP_VERSION_ID;')"; \
    # 旧 Debian（buster/stretch）はアーカイブへ切替（apt-get update を通すため）
    . /etc/os-release; \
    case "${VERSION_CODENAME:-}" in \
        buster|stretch) \
            sed -i 's|deb.debian.org|archive.debian.org|g; s|security.debian.org|archive.debian.org|g; /-updates/d' /etc/apt/sources.list; \
            ;; \
    esac; \
    apt-get update; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get install -y --no-install-recommends \
        libfreetype6-dev \
        libmagickwand-dev \
        libjpeg62-turbo-dev \
        libmcrypt-dev \
        libpng-dev \
        libicu-dev \
        libzip-dev \
        libonig-dev \
        libssl-dev \
        build-essential \
    ; \
    apt-get install -y --no-install-recommends \
        jpegoptim \
        optipng \
        gifsicle \
        sendmail \
        git-core \
        openssh-client \
        openssl \
        python3 \
        zip \
        unzip \
    ; \
    # gd の configure フラグは PHP 7.4 で変わる
    if [ "$PHP_ID" -ge 70400 ]; then \
        docker-php-ext-configure gd --with-freetype --with-jpeg; \
    else \
        docker-php-ext-configure gd --with-freetype-dir=/usr --with-jpeg-dir=/usr; \
    fi; \
    docker-php-ext-install -j"$(nproc)" gd zip; \
    # mbstring は公式イメージに静的組込み済みのため install しない（全対応バージョンで確認済み）
    docker-php-ext-install gettext pdo_mysql mysqli bcmath exif; \
    # docker-php-ext-install は内部で enable まで行うため、個別の enable は不要
    php -m | grep -qi 'Zend OPcache' || docker-php-ext-enable opcache; \
    # 版依存の pecl 拡張（古い PHP では対応する旧版へフォールバック）
    REDIS_VER="$REDIS_VERSION"; \
    XDEBUG_VER="$XDEBUG_VERSION"; \
    if [ "$PHP_ID" -lt 70400 ]; then REDIS_VER=5.3.7; fi; \
    if [ "$PHP_ID" -lt 80000 ]; then XDEBUG_VER=3.1.6; fi; \
    pecl install "apcu-${APCU_VERSION}"; \
    pecl install "redis-${REDIS_VER}"; \
    pecl install "imagick-${IMAGICK_VERSION}"; \
    pecl install "xdebug-${XDEBUG_VER}"; \
    pecl install "pcov-${PCOV_VERSION}"; \
    docker-php-ext-enable apcu redis imagick pcov; \
    ln -sf /usr/bin/python3 /usr/bin/python; \
    a2enmod headers mime expires deflate rewrite ssl; \
    # www-data のホームは既定で /var/www（= APACHE_DOCUMENT_ROOT の親）。
    # 一部の Debian 版(shadow-utils)は usermod -u 実行時にホーム配下を再帰 chown する
    # ため、PUID/PGID でマウント済みプロジェクト全体が巻き込まれ得る。
    # ホームを無関係な場所へ切り離し、entrypoint.sh 側は変更せずに無効化する。
    usermod -d /nonexistent www-data; \
    # ---- ビルド専用パッケージを除去（公式 PHP イメージと同じ apt-mark パターン） ----
    # 1) いったん全パッケージを auto 扱いにし、元々 manual だったもの（ベースイメージ
    #    由来）だけ復元する
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    # 2) 自前ビルドした拡張(.so)が実際にリンクしている共有ライブラリの提供パッケージを
    #    検出して manual に固定する（apt はこれらの .so の存在を知らないため、
    #    自動では依存関係として認識されない）。走査対象は拡張の .so のみに絞り、
    #    スクリプト等を ldd に渡してノイズが出ないようにする。
    # Debian は /lib が /usr/lib への symlink（usrmerge）なので、ldd が返す
    # パスのままでは dpkg-query --search が一致しない。readlink -f で
    # symlink（/lib → /usr/lib、バージョンなし .so → 実体）を解決してから渡す。
    find /usr/local/lib/php/extensions -name '*.so' 2>/dev/null \
        | xargs -r -I{} ldd {} 2>/dev/null \
        | grep -E ' => /' \
        | awk '{print $3}' \
        | xargs -r -I{} readlink -f {} \
        | sort -u \
        | xargs -r dpkg-query --search 2>/dev/null \
        | cut -d: -f1 \
        | sort -u \
        | xargs -r apt-mark manual \
    ; \
    # 3) 開発用イメージとして明示的に残したい CLI ツール（ビルド後も使う）
    apt-mark manual git openssh-client python3 sendmail jpegoptim optipng gifsicle zip unzip openssl 2>/dev/null || true; \
    # 4) 上記以外（build-essential・*-dev ヘッダ等）を自動判定して除去
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# composer（インストーラの署名を SHA-384 で検証してから実行：改ざん対策）
RUN set -eux; \
    curl -fsSL -o /tmp/composer-setup.php https://getcomposer.org/installer; \
    curl -fsSL -o /tmp/composer-setup.sig https://composer.github.io/installer.sig; \
    php -r "\$sig = trim(file_get_contents('/tmp/composer-setup.sig')); \$hash = hash('sha384', file_get_contents('/tmp/composer-setup.php')); if (\$sig !== \$hash) { fwrite(STDERR, 'Composer installer integrity check failed'.PHP_EOL); exit(1); }"; \
    php /tmp/composer-setup.php --no-ansi --install-dir=/usr/local/bin --filename=composer; \
    composer --ansi --version --no-interaction; \
    rm -f /tmp/composer-setup.php /tmp/composer-setup.sig

# php.ini
COPY config/php.ini /usr/local/etc/php/

# PCOV（コードカバレッジ用。既定は無効。実行時に -d pcov.enabled=1 で有効化）
COPY config/pcov.ini /usr/local/etc/php/conf.d/zz-pcov.ini

# xdebug 設定は conf.d に置かず、entrypoint が有効化時のみ読み込む
COPY config/xdebug.ini /usr/local/etc/php/xdebug.ini

# apache
RUN echo "Mutex posixsem" >> /etc/apache2/apache2.conf; \
    # APACHE_DOCUMENT_ROOT の反映を毎回オリジナルから冪等に生成するため退避しておく
    # （entrypoint.sh 参照）。2回目以降の起動でも最新の値が反映される。
    cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf.orig; \
    for f in /etc/apache2/sites-available/*.conf /etc/apache2/conf-available/*.conf; do \
        cp "$f" "$f.orig"; \
    done

COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

# Apache が接続を受け付けているかの簡易チェック（接続不可のときだけ unhealthy）
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -sS -o /dev/null http://localhost/ || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
