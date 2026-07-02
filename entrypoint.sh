#!/bin/bash

set -eo pipefail
shopt -s nullglob

# sendmail 用のホスト名解決
echo "127.0.0.1 $(hostname).localdomain $(hostname)" >> /etc/hosts

# --- UID/GID マッピング（主に Linux ホストでのボリューム所有権対策）---
# ACMS_UID / ACMS_GID を渡すと Apache 実行ユーザ(www-data)の uid/gid を合わせる。
# 未指定なら従来どおり（何もしない）。
if [ -n "${ACMS_GID}" ] && [ "${ACMS_GID}" != "$(id -g www-data)" ]; then
    groupmod -o -g "${ACMS_GID}" www-data
fi
if [ -n "${ACMS_UID}" ] && [ "${ACMS_UID}" != "$(id -u www-data)" ]; then
    usermod -o -u "${ACMS_UID}" www-data
fi

# --- Xdebug の実行時トグル ---
# ACMS_XDEBUG=true のときだけ xdebug を有効化し、opcache を無効化する。
# opcache の無効化は ini 設定で行う（PHP 8.5 は opcache が静的組込みのため
# ini 削除では止められない。opcache.enable=0 なら静的でも確実に無効化できる）。
XDEBUG_INI="/usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini"
XDEBUG_SETTINGS="/usr/local/etc/php/conf.d/zzz-xdebug-settings.ini"
OPCACHE_OFF="/usr/local/etc/php/conf.d/zzz-disable-opcache.ini"
if [ "${ACMS_XDEBUG}" = "true" ]; then
    docker-php-ext-enable xdebug
    cp /usr/local/etc/php/xdebug.ini "${XDEBUG_SETTINGS}"
    printf 'opcache.enable=0\nopcache.enable_cli=0\n' > "${OPCACHE_OFF}"
    echo "[entrypoint] Xdebug: enabled (opcache disabled)"
else
    # 再起動時に備えて有効化状態を解除する
    rm -f "${XDEBUG_INI}" "${XDEBUG_SETTINGS}" "${OPCACHE_OFF}"
    echo "[entrypoint] Xdebug: disabled"
fi

# document root
echo "${APACHE_DOCUMENT_ROOT}"

INIT_FILE="/var/www/init.txt"

if test "${APACHE_DOCUMENT_ROOT}" != ""; then
    if [ ! -e $INIT_FILE ]; then
        sed -ri -e "s!/var/www/html!${APACHE_DOCUMENT_ROOT}!g" /etc/apache2/sites-available/*.conf
        sed -ri -e "s!/var/www/!${APACHE_DOCUMENT_ROOT}!g" /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf
        touch $INIT_FILE
    fi
fi

service sendmail restart
service apache2 restart

trap 'service apache2 stop; exit 0' TERM

while :
do
    sleep 1
done
