# syntax=docker/dockerfile:1

# ビルドするPHPバージョンは docker-bake.hcl / CI のマトリクスから渡す。
# ローカルで単体ビルドする場合は --build-arg PHP_VERSION=8.3 を指定する。
ARG PHP_VERSION=8.3
FROM php:${PHP_VERSION}-apache

# pecl 拡張のバージョンは再現性のため固定（PHP 8.0〜8.5 でビルド確認済み）。
# 更新は手動（dependabot は pecl を追わない）。新 PHP 対応時はここを見直す。
ARG APCU_VERSION=5.1.28
ARG REDIS_VERSION=6.3.0
ARG IMAGICK_VERSION=3.8.1
ARG XDEBUG_VERSION=3.5.3
ARG PCOV_VERSION=1.0.12

# ---- OS パッケージ & PHP 拡張 ----
# xdebug/pcov は常時インストールしておき、有効化は実行時に行う。
#  - xdebug: ACMS_XDEBUG=true のときだけ entrypoint が有効化（-xdebug 専用イメージ不要）
#  - pcov:   既定は pcov.enabled=0（カバレッジ取得時のみ -d pcov.enabled=1）
# OPcache は PHP 8.5 で静的組込みのため install せず、未ロード時のみ enable する
# （8.0=要enable / 8.3=標準で有効 / 8.5=静的、を1行で吸収）。
RUN set -eux; \
    apt-get update; \
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
        jpegoptim \
        optipng \
        gifsicle \
        sendmail \
        git-core \
        build-essential \
        openssl \
        python3 \
        zip \
        unzip \
    ; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" gd zip; \
    docker-php-ext-install mbstring gettext pdo_mysql mysqli bcmath exif; \
    docker-php-ext-enable mysqli; \
    php -m | grep -qi 'Zend OPcache' || docker-php-ext-enable opcache; \
    pecl install "apcu-${APCU_VERSION}"; \
    pecl install "redis-${REDIS_VERSION}"; \
    pecl install "imagick-${IMAGICK_VERSION}"; \
    pecl install "xdebug-${XDEBUG_VERSION}"; \
    pecl install "pcov-${PCOV_VERSION}"; \
    docker-php-ext-enable apcu redis imagick pcov; \
    ln -sf /usr/bin/python3 /usr/bin/python; \
    a2enmod headers mime expires deflate rewrite ssl; \
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
RUN echo "Mutex posixsem" >> /etc/apache2/apache2.conf

COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

# Apache が接続を受け付けているかの簡易チェック（接続不可のときだけ unhealthy）
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -sS -o /dev/null http://localhost/ || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
