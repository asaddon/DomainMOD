# ------------------------------------------------------------------------------
# DomainMOD Dockerfile (Optimized & Dynamic Metadata)
# ------------------------------------------------------------------------------
    FROM php:8.2.9-apache

    # ------------------------------------------------------------------------------
    # Build metadata (dynamic at build time)
    # ------------------------------------------------------------------------------
    ARG SOFTWARE_VERSION=4.23.0
    ARG BUILD_DATE="1970-01-01T00:00:00Z"
    ARG COMMIT_ID=unknown
    ENV SOFTWARE_VERSION=${SOFTWARE_VERSION}
    
    # User configuration
    ENV CUSER=domainmod
    ENV PUID=1000
    ENV PGID=1000
    
    # Default locale
    ENV LANG=en_CA.UTF-8
    ENV LC_ALL=en_CA.UTF-8
    
    # ------------------------------------------------------------------------------
    # Locales list (looped for optimization)
    # ------------------------------------------------------------------------------
    ENV LOCALES="en_CA.UTF-8 en_US.UTF-8 de_DE.UTF-8 es_ES.UTF-8 fr_FR.UTF-8 it_IT.UTF-8 nl_NL.UTF-8 pl_PL.UTF-8 pt_PT.UTF-8 ru_RU.UTF-8 ar_SA.UTF-8 bn_BD.UTF-8 zh_CN.UTF-8 zh_TW.UTF-8 hi_IN.UTF-8 id_ID.UTF-8 ja_JP.UTF-8 ko_KR.UTF-8 mr_IN.UTF-8 fa_IR.UTF-8 pt_BR.UTF-8 ta_IN.UTF-8 te_IN.UTF-8 tr_TR.UTF-8 ur_PK.UTF-8 vi_VN.UTF-8"
    
    # ------------------------------------------------------------------------------
    # Install system dependencies, PHP extensions, and generate locales
    # ------------------------------------------------------------------------------
    RUN apt-get update && apt-get install -y \
            git curl cron locales gettext \
            libpng-dev libonig-dev libxml2-dev libzip-dev \
        && docker-php-ext-install gettext pdo_mysql mysqli mbstring exif pcntl bcmath gd zip \
        && docker-php-ext-enable gettext sodium \
        && for loc in $LOCALES; do echo "$loc UTF-8" >> /etc/locale.gen; done \
        && locale-gen \
        && apt-get clean && rm -rf /var/lib/apt/lists/*
    
    # ------------------------------------------------------------------------------
    # Create DomainMOD user
    # ------------------------------------------------------------------------------
    RUN groupadd -g ${PGID} ${CUSER} \
        && useradd -u ${PUID} -g ${PGID} -s /bin/bash -m ${CUSER}
    
    # ------------------------------------------------------------------------------
    # Apache settings
    # ------------------------------------------------------------------------------
    RUN a2enmod rewrite headers
    
    # ------------------------------------------------------------------------------
    # Cron setup (runs every 10 minutes)
    # ------------------------------------------------------------------------------
    RUN echo "*/10 * * * * ${CUSER} /usr/local/bin/php -q /var/www/html/cron.php > /dev/null" > /etc/cron.d/cron \
        && chmod 0644 /etc/cron.d/cron \
        && crontab /etc/cron.d/cron
    
    # ------------------------------------------------------------------------------
    # PHP configuration
    # ------------------------------------------------------------------------------
    RUN { \
            echo "allow_url_fopen = On"; \
            echo "upload_max_filesize = 10M"; \
            echo "post_max_size = 10M"; \
            echo "memory_limit = 256M"; \
            echo "max_execution_time = 300"; \
        } > /usr/local/etc/php/conf.d/domainmod.ini
    
    # ------------------------------------------------------------------------------
    # Copy DomainMOD fork
    # ------------------------------------------------------------------------------
    COPY . /var/www/html/
    
    # ------------------------------------------------------------------------------
    # Update SOFTWARE_VERSION in software.inc.php
    # ------------------------------------------------------------------------------
    RUN sed -i "s/const SOFTWARE_VERSION = '.*';/const SOFTWARE_VERSION = '${SOFTWARE_VERSION}';/" /var/www/html/_includes/software.inc.php

    # ------------------------------------------------------------------------------
    # Permissions
    # ------------------------------------------------------------------------------
    RUN chown -R ${CUSER}:www-data /var/www/html \
        && chmod -R 755 /var/www/html \
        && mkdir -p /var/www/html/temp \
        && chown -R ${CUSER}:www-data /var/www/html/temp \
        && chmod -R 775 /var/www/html/temp
    
    # ------------------------------------------------------------------------------
    # Composer install if needed
    # ------------------------------------------------------------------------------
    RUN if [ -f "/var/www/html/composer.json" ]; then \
            curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer && \
            cd /var/www/html && composer install --no-dev --optimize-autoloader --no-interaction; \
        fi
    
    WORKDIR /var/www/html
    
    # ------------------------------------------------------------------------------
    # Entrypoint: start cron then Apache
    # ------------------------------------------------------------------------------
    RUN echo '#!/bin/bash' > /usr/local/bin/entrypoint.sh \
        && echo 'service cron start' >> /usr/local/bin/entrypoint.sh \
        && echo 'exec "$@"' >> /usr/local/bin/entrypoint.sh \
        && chmod +x /usr/local/bin/entrypoint.sh
    
    ENTRYPOINT ["bash", "/usr/local/bin/entrypoint.sh"]
    
    # ------------------------------------------------------------------------------
    # Expose Apache
    # ------------------------------------------------------------------------------
    EXPOSE 80
    
    # ------------------------------------------------------------------------------
    # Metadata labels
    # ------------------------------------------------------------------------------
    LABEL org.opencontainers.image.authors="greg@greg.ca" \
          org.opencontainers.image.version="${SOFTWARE_VERSION}" \
          org.opencontainers.image.created="${BUILD_DATE}" \
          org.opencontainers.image.revision="${COMMIT_ID}"
    
    CMD ["/usr/sbin/apache2ctl", "-D", "FOREGROUND"]