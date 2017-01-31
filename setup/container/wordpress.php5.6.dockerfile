# Forked from https://github.com/docker-library/wordpress/blob/master/php5.6/apache/Dockerfile
FROM php:5.6-apache

# PHP Extensions - install the PHP extensions we need
RUN set -ex; \
	apt-get update; \
	apt-get install -y libjpeg-dev libpng12-dev; \
	rm -rf /var/lib/apt/lists/*; \
	docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr; \
	docker-php-ext-install gd mysqli opcache;
# TODO consider removing the *-dev deps and only keeping the necessary lib* packages

# PHP.ini - set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=2'; \
		echo 'opcache.fast_shutdown=1'; \
		echo 'opcache.enable_cli=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

# Environment Variables - ARG for build, ENV for runtime.
# https://wordpress.org/download/release-archive/
ARG WORDPRESS_VERSION=4.6.1
ENV WORDPRESS_VERSION ${WORDPRESS_VERSION}
# SHA1 Checksum computed on the downloaded file, as a way to verify the content authenticity.
ARG WORDPRESS_SHA1=027e065d30a64720624a7404a1820e6c6fff1202
ENV WORDPRESS_SHA1 ${WORDPRESS_SHA1}
# Wordpress download: Important: Wordpress cannot be downloaded directly to the destination folder, as it is going to be override by volume.
RUN set -ex; \
	curl -o wordpress.tar.gz -fSL "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz"; \
	echo "${WORDPRESS_SHA1} *wordpress.tar.gz" | sha1sum -c -; \
	# upstream tarballs include ./wordpress/ so this gives us /usr/src/wordpress
	tar -xzf wordpress.tar.gz -C /usr/src/; \
	rm wordpress.tar.gz; \
	chown -R www-data:www-data /usr/src/wordpress

# Environment Variables & Arguments
# default value is override if build argument is specified in docker compose.
ARG DEPLOYMENT=production
ENV DEPLOYMENT ${DEPLOYMENT}

COPY ./setup/shellScript/ /tmp/shellScript/
RUN set -ex; \
    # Apparently when copied from windows, execution permissions should be granted.
    find /tmp/shellScript/ -type f -exec chmod +x {} \; \
	; \
	# update and install essentials:
	apt-get -y update; apt-get -y upgrade; apt-get -y install vim; apt-get -y install nano; pecl install zip; \
	#  Apache
	# RUN apt-get install libapache2-mod-macro;
	# Apache mods to enable: Reverse proxy, macro, ssl, vhost_alias
	a2enmod rewrite expires xml2enc proxy proxy_ajp proxy_http deflate headers proxy_balancer proxy_connect proxy_html macro ssl vhost_alias headers; \
	# Apache enable sites configuration and remove default.
	rm -r /etc/apache2/sites-enabled/*; \
	# Install Dependencies:
	if [ "${DEPLOYMENT}" = "production" ]; then \
    	/tmp/shellScript/git.installation.sh; \
		/tmp/shellScript/nodejs.installation.sh; \
	    /tmp/shellScript/gulp.installation.sh; \
		/tmp/shellScript/rsync.installation.sh; \
	elif [ "${DEPLOYMENT}" = "development" ]; then \
    	/tmp/shellScript/git.installation.sh; \
		/tmp/shellScript/nodejs.installation.sh; \
	    /tmp/shellScript/gulp.installation.sh; \
		/tmp/shellScript/rsync.installation.sh; \
	fi;

# copy distribution to image.
COPY ./distribution /tmp/distribution
COPY ./setup/build/gulp_buildTool /tmp/build/gulp_buildTool
COPY ./privateRepository/ /tmp/content/
WORKDIR /tmp/build/gulp_buildTool
RUN set -ex; \
	# Copy configuration files.
	node --harmony `which gulp` copy:conf; \
	if [ "${DEPLOYMENT}" = "production" ]; then \
		# Gulp copy
		node --harmony `which gulp` copy:distribution; \
	fi;

# Volumes:
VOLUME /app/

# Apparently when copied from windows, execution permissions should be granted.
COPY ./setup/container/shellScript/wordpressContainer.entrypoint.sh /tmp/shellScript/
RUN find /tmp/shellScript/ -type f -exec chmod +x {} \;

# RUN find /usr/local/bin/ -type f -exec chmod +x {} \;
ENTRYPOINT ["/tmp/shellScript/wordpressContainer.entrypoint.sh"]

CMD ["apache2-foreground"]
