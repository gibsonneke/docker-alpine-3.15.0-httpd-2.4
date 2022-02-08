FROM alpine:3.15.0

CMD ["/bin/sh"]

RUN /bin/sh -c set -x && adduser -u 82 -D -S -G www-data www-data

ENV HTTPD_PREFIX=/usr/local/apache2
ENV PATH=/usr/local/apache2/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN mkdir -p "$HTTPD_PREFIX" && chown www-data:www-data "$HTTPD_PREFIX"

RUN apk add --no-cache openssh-client git patch shadow

WORKDIR /usr/local/apache2/htdocs

ENV HTTPD_VERSION=2.4.52
ENV HTTPD_SHA256=0127f7dc497e9983e9c51474bed75e45607f2f870a7675a86dc90af6d572f5c9
ENV HTTPD_PATCHES=
ENV APACHE_DIST_URLS \
	https://www.apache.org/dyn/closer.cgi?action=download&filename= \
	https://www-us.apache.org/dist/ \
	https://www.apache.org/dist/ \
	https://archive.apache.org/dist/

RUN set -eux && runDeps='apr-dev apr-util-dev apr-util-ldap perl' && apk update && apk add --no-cache --virtual .build-deps $runDeps coreutils dpkg-dev dpkg gcc gnupg libc-dev libressl libressl-dev libxml2-dev lua-dev make nghttp2-dev pcre-dev tar zlib-dev \
    && ddist() { local f="$1"; shift; local distFile="$1"; shift; local success=; local distUrl=; for distUrl in $APACHE_DIST_URLS; do if wget -O "$f" "$distUrl$distFile" && [ -s "$f" ]; then success=1; break; fi; done; [ -n "$success" ]; } \
    && ddist 'httpd.tar.bz2' "httpd/httpd-$HTTPD_VERSION.tar.bz2"; echo "$HTTPD_SHA256 *httpd.tar.bz2" | sha256sum -c - \
    && ddist 'httpd.tar.bz2.asc' "httpd/httpd-$HTTPD_VERSION.tar.bz2.asc"; export GNUPGHOME="$(mktemp -d)"; for key in 26F51EF9A82F4ACB43F1903ED377C9E7D1944C66; do gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys "$key"; done; gpg --batch --verify httpd.tar.bz2.asc httpd.tar.bz2; rm -rf "$GNUPGHOME" httpd.tar.bz2.asc; mkdir -p src; tar -xf httpd.tar.bz2 -C src --strip-components=1; rm httpd.tar.bz2; cd src; patches() { while [ "$#" -gt 0 ]; do local patchFile="$1"; shift; local patchSha256="$1"; shift; ddist "$patchFile" "httpd/patches/apply_to_$HTTPD_VERSION/$patchFile"; echo "$patchSha256 *$patchFile" | sha256sum -c -; patch -p0 < "$patchFile"; rm -f "$patchFile"; done; }; patches $HTTPD_PATCHES; gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; ./configure --build="$gnuArch" --prefix="$HTTPD_PREFIX" --enable-mods-shared=reallyall --enable-mpms-shared=all; 	make -j "$(nproc)"; make install; cd ..; rm -r src; cd ..; rm -r man manual; sed -ri -e 's!^(\s*CustomLog)\s+\S+!\1 /proc/self/fd/1!g' -e 's!^(\s*ErrorLog)\s+\S+!\1 /proc/self/fd/2!g' "$HTTPD_PREFIX/conf/httpd.conf"; runDeps="$runDeps $(scanelf --needed --nobanner --format '%n#p' --recursive /usr/local | tr ',' '\n' | sort -u | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' 	)"; apk add --virtual .httpd-rundeps $runDeps; apk del .build-deps

COPY httpd-foreground /usr/local/bin/httpd-foreground

EXPOSE 80/tcp

CMD ["httpd-foreground"]

ENV DOCKER_USER_ID=501
ENV DOCKER_USER_GID=20

RUN /bin/sh -c set -x && groupmod -g 567 dialout && groupmod -g ${DOCKER_USER_GID} www-data && usermod -g ${DOCKER_USER_GID} -u ${DOCKER_USER_ID} www-data
RUN /bin/sh -c set -x && chown www-data:www-data /home/www-data && chown www-data:www-data /usr/local/apache2
