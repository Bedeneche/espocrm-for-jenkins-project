# EspoCRM ships no production Dockerfile in its source repo, so this one
# builds the app from source (multi-stage) and runs it on PHP 8.3 + Apache.

# ---------- Stage 1: build from source ----------
FROM php:8.3-cli AS builder
COPY --from=ghcr.io/mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
ENV COMPOSER_ALLOW_SUPERUSER=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends git unzip curl ca-certificates \
 && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && install-php-extensions pdo_mysql gd zip intl exif pcntl posix bcmath \
 && npm install -g grunt-cli \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .
RUN npm ci || npm install
# Default grunt task builds the distributable into build/EspoCRM-<version>
RUN grunt

# ---------- Stage 2: runtime ----------
FROM php:8.3-apache
COPY --from=ghcr.io/mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

RUN install-php-extensions pdo_mysql gd zip intl exif pcntl posix bcmath opcache \
 && a2enmod rewrite headers \
 && printf '%s\n' \
      'memory_limit=256M' \
      'max_execution_time=180' \
      'max_input_time=180' \
      'post_max_size=50M' \
      'upload_max_filesize=50M' \
      > /usr/local/etc/php/conf.d/espocrm.ini \
 && printf '%s\n' \
      '<Directory /var/www/html>' \
      '    AllowOverride All' \
      '</Directory>' \
      > /etc/apache2/conf-available/espocrm.conf \
 && a2enconf espocrm

COPY --from=builder --chown=www-data:www-data /src/build/EspoCRM-*/ /var/www/html/

EXPOSE 80
CMD ["apache2-foreground"]
