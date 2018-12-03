FROM dockette/php:7.2-fpm

# Set up some useful environment variables
ENV DEBIAN_FRONTEND noninteractive

ENV WP_ROOT /var/www/public/blog
ENV WP_VERSION 4.9.7
ENV WP_SHA1 7bf349133750618e388e7a447bc9cdc405967b7d
ENV WP_DOWNLOAD_URL https://wordpress.org/wordpress-$WP_VERSION.tar.gz

RUN apt-get update && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    lsb-release \
    curl \
    locales \
    runit \
    syslog-ng \
    gnupg2 \
    && rm -rf /var/lib/apt/lists/*

ENV LANGUAGE en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen en_US.UTF-8

RUN echo "deb http://nginx.org/packages/debian/ $(lsb_release -sc) nginx" > \
      /etc/apt/sources.list.d/nginx.list \
    && curl -vs http://nginx.org/keys/nginx_signing.key | apt-key add -

RUN apt-get update && apt-get install -y \
    nginx imagemagick \
    && rm -rf /var/lib/apt/lists/*

# Temporary, until Docker's built-in init becomes more wide-spread
ADD https://github.com/Yelp/dumb-init/releases/download/v1.2.1/dumb-init_1.2.1_amd64 /usr/bin/dumb-init
RUN chmod +x /usr/bin/dumb-init

RUN mkdir -p /var/run/php \
    && mkdir -p $(dirname $WP_ROOT)

# Configure PHP
RUN echo 'file_uploads = On\n\
allow_url_fopen = On\n\
upload_max_filesize = 100M\n\
cgi.fix_pathinfo = 0\n\
date.timezone = Europe/London'\
>> /etc/php/7.2/fpm/php.ini

# Since we want to be able to update WordPress seamlessly, we need to
# declare a volume that is mounted in place of the default wp-content, so
# we can swap WP versions and re-use the same wp-content
VOLUME $WP_ROOT/wp-content
WORKDIR $WP_ROOT/wp-content

# For convenience, set www-data to UID and GID 1001
RUN groupmod -g 1001 www-data \
    && usermod -u 1001 www-data

# Download and extract WordPress into /var/www/public and rename wordpress as /blog
RUN curl -o wordpress.tar.gz -SL $WP_DOWNLOAD_URL \
    && echo "$WP_SHA1 *wordpress.tar.gz" | sha1sum -c - \
    && tar -xzf wordpress.tar.gz -C $(dirname $WP_ROOT) \
    && rm -rf $(dirname $WP_ROOT)/wordpress/wp-content \
    && mv $(dirname $WP_ROOT)/wordpress/* $WP_ROOT/ \
    && rm -rf $(dirname $WP_ROOT)/wordpress \
    && rm -f wordpress.tar.gz

# Create an empty directory in which we can mount secrets
VOLUME /etc/secrets

# Copy our custom wp-config.php over. This is arguably the most important
# part/trick, that makes WordPress container-friendly. Instead of hard-coding
# configuraion, we just loop through all environment variables and define
# them for use inside WordPress/PHP
COPY wp-config.php $WP_ROOT
RUN chown -R www-data:www-data $(dirname $WP_ROOT) \
    && chmod 640 $WP_ROOT/wp-config.php

COPY rootfs /

# We only expose port 80, but not 443. In a proper "containerized" manner
# HTTPS should be handled by a separate Nginx container/reverse proxy
EXPOSE 80

ENTRYPOINT ["/usr/bin/dumb-init", "--"]

CMD ["runsvdir", "-P", "/etc/service"]
