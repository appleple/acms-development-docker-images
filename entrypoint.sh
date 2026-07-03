#!/bin/bash

set -eo pipefail
shopt -s nullglob

# sendmail 用のホスト名解決
echo "127.0.0.1 $(hostname).localdomain $(hostname)" >> /etc/hosts

# --- UID/GID マッピング（主に Linux ホストでのボリューム所有権対策）---
# PUID / PGID を渡すと Apache 実行ユーザ(www-data)の uid/gid を合わせる。
# 未指定なら従来どおり（何もしない）。
if [ -n "${PGID}" ] && [ "${PGID}" != "$(id -g www-data)" ]; then
    groupmod -o -g "${PGID}" www-data
fi
if [ -n "${PUID}" ] && [ "${PUID}" != "$(id -u www-data)" ]; then
    usermod -o -u "${PUID}" www-data
fi

# --- Xdebug の実行時トグル ---
# XDEBUG=true のときだけ xdebug を有効化し、opcache を無効化する。
# opcache の無効化は ini 設定で行う（PHP 8.5 は opcache が静的組込みのため
# ini 削除では止められない。opcache.enable=0 なら静的でも確実に無効化できる）。
XDEBUG_INI="/usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini"
XDEBUG_SETTINGS="/usr/local/etc/php/conf.d/zzz-xdebug-settings.ini"
OPCACHE_OFF="/usr/local/etc/php/conf.d/zzz-disable-opcache.ini"
if [ "${XDEBUG}" = "true" ]; then
    docker-php-ext-enable xdebug
    cp /usr/local/etc/php/xdebug.ini "${XDEBUG_SETTINGS}"
    printf 'opcache.enable=0\nopcache.enable_cli=0\n' > "${OPCACHE_OFF}"
    echo "[entrypoint] Xdebug: enabled (opcache disabled)"
else
    # 再起動時に備えて有効化状態を解除する
    rm -f "${XDEBUG_INI}" "${XDEBUG_SETTINGS}" "${OPCACHE_OFF}"
    echo "[entrypoint] Xdebug: disabled"
fi

# --- DocumentRoot の反映 ---
# 状態ファイルで「初回かどうか」を判定するのではなく、ビルド時に退避した
# オリジナルの設定ファイル(*.orig)から毎回冪等に再生成する。これにより
# 再起動のたびに APACHE_DOCUMENT_ROOT の最新値が確実に反映される。
# 置換先の値に sed のメタ文字（/ & \）が含まれても壊れないようエスケープする。
echo "${APACHE_DOCUMENT_ROOT}"

if [ -n "${APACHE_DOCUMENT_ROOT}" ]; then
    esc_root=$(printf '%s' "${APACHE_DOCUMENT_ROOT}" | sed -e 's/[\/&\\]/\\&/g')
    for f in /etc/apache2/sites-available/*.conf.orig; do
        sed -re "s/\/var\/www\/html/${esc_root}/g" "$f" > "${f%.orig}"
    done
    for f in /etc/apache2/apache2.conf.orig /etc/apache2/conf-available/*.conf.orig; do
        sed -re "s/\/var\/www\//${esc_root}\//g" "$f" > "${f%.orig}"
    done
fi

service sendmail restart

# apache2 をこのシェルの exec で置き換え、PID1 にする。
# こうすることで apache2 がクラッシュ/OOM-killされた場合にコンテナ自体が
# 終了し、docker の restart ポリシー（restart: always 等）で正しく
# 自動復旧できるようになる（バックグラウンド常駐 + sleep ループ方式だと、
# apache が死んでも PID1 が生き残り「Running」のまま復旧されない）。
exec /usr/local/bin/apache2-foreground
