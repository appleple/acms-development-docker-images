FROM php:8.4-apache-bookworm

# ロケール設定
ENV LANG=C.UTF-8

# extension & tool install
RUN apt-get update \
    && apt-get install -y \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libicu-dev \
        libzip-dev \
        libonig-dev \
        libssl-dev \
        libmagickwand-dev \
        libheif-dev \
        libde265-dev \
        x265 \
        imagemagick \
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
        curl \
        gnupg \
    && docker-php-ext-configure gd --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd zip mbstring gettext pdo_mysql mysqli opcache bcmath \
    && docker-php-ext-enable mysqli \
    && pecl install apcu redis imagick \
    && docker-php-ext-enable apcu redis imagick \
    && ln -s /usr/bin/python3 /usr/bin/python \
    && a2enmod headers mime expires deflate rewrite ssl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Composer
RUN curl -sS https://getcomposer.org/installer | php \
    && mv composer.phar /usr/local/bin/composer

# Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g npm

# PHP設定
COPY config/php.ini /usr/local/etc/php/

# Apache設定
RUN echo "Mutex posixsem" >> /etc/apache2/apache2.conf

# Entrypoint
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]