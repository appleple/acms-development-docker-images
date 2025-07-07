FROM php:8.4-apache-bookworm

# ロケール設定（文字化け対策）
ENV LANG=C.UTF-8

# extension
RUN apt-get update \
    && apt-get install -y \
        libfreetype6-dev \
        libmagickwand-dev \
        libjpeg62-turbo-dev \
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
    && docker-php-ext-configure gd --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-install -j$(nproc) zip \
    && docker-php-ext-install mbstring \
    && docker-php-ext-install gettext \
    && docker-php-ext-install pdo_mysql \
    && docker-php-ext-install mysqli \
    && docker-php-ext-install opcache \
    && docker-php-ext-install bcmath \
    && docker-php-ext-enable mysqli \
    && pecl install apcu \
        redis \
    && docker-php-ext-enable apcu \
    && docker-php-ext-enable redis \
    && ln -s /usr/bin/python3 /usr/bin/python \
    && a2enmod headers mime expires deflate rewrite ssl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# composer
RUN curl -sS https://getcomposer.org/installer | php \
    && mv composer.phar /usr/local/bin/composer

# node
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g npm

# php.ini
COPY config/php.ini /usr/local/etc/php/

# apache
RUN echo "Mutex posixsem" >> /etc/apache2/apache2.conf

COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]