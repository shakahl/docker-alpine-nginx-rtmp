FROM alpine:3.4
MAINTAINER Soma Szélpál <szelpalsoma@gmail.com>

ENV NGINX_VERSION 1.13.1
ENV NGINX_RTMP_VERSION 1.1.11
ENV NGINX_DEVEL_KIT_VERSION=0.3.0
ENV LUA_NGINX_MODULE_VERSION=0.10.8
ENV LUAJIT_VERSION=2.0.5
ENV FFMPEG_VERSION 3.3.1

ENV LUAJIT_LIB /usr/local/lib
ENV LUAJIT_INC /usr/local/include/luajit-2.0

ENV NGINX_DEVEL_KIT ngx_devel_kit-${NGINX_DEVEL_KIT_VERSION}
ENV LUA_NGINX_MODULE lua-nginx-module-${LUA_NGINX_MODULE_VERSION}

# Common dependencies
ENV DEPS_COMMON="bash nano lua"

# Common build tools
ENV DEPS_BUILD_TOOLS="git unzip gcc binutils-libs binutils build-base libgcc make pkgconf pkgconfig openssl openssl-dev ca-certificates pcre nasm yasm yasm-dev coreutils musl-dev libc-dev pcre-dev zlib-dev lua-dev"

# FFMPEG dependencies
ENV DEPS_FFMPEG "gnutls-dev libogg-dev libvpx-dev libvorbis-dev freetype-dev libass-dev libwebp-dev rtmpdump-dev libtheora-dev lame-dev xvidcore-dev imlib2-dev x264-dev bzip2-dev perl-dev libvpx-dev sdl2-dev libxfixes-dev libva-dev alsa-lib-dev v4l-utils-dev opus-dev x265-dev"

# Installing common dependencies
RUN apk update && apk add --virtual .common-dependencies ${DEPS_COMMON}

# Installing build dependencies
RUN	apk update && apk add --virtual .build-dependencies	${DEPS_BUILD_TOOLS}

# Build Luarocks.
RUN cd /tmp && git clone https://github.com/keplerproject/luarocks.git \
  && cd luarocks \
  && ./configure \
  && make build install
RUN rm -rf /tmp/luarocks

# Get LuaJIT.
RUN cd /tmp \
  && wget http://luajit.org/download/LuaJIT-${LUAJIT_VERSION}.tar.gz \
  && tar zxf LuaJIT-${LUAJIT_VERSION}.tar.gz \
  && rm LuaJIT-${LUAJIT_VERSION}.tar.gz

RUN cd /tmp/LuaJIT-${LUAJIT_VERSION} && make && make install

# Get nginx source.
RUN cd /tmp \
  && wget http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz \
  && tar zxf nginx-${NGINX_VERSION}.tar.gz \
  && rm nginx-${NGINX_VERSION}.tar.gz

# Get nginx-rtmp module.
RUN cd /tmp \
  && wget https://github.com/arut/nginx-rtmp-module/archive/v${NGINX_RTMP_VERSION}.tar.gz \
  && tar zxf v${NGINX_RTMP_VERSION}.tar.gz \
  && rm v${NGINX_RTMP_VERSION}.tar.gz

# Get ngx_devel_kit.
RUN cd /tmp \
  && wget https://github.com/simpl/ngx_devel_kit/archive/v${NGINX_DEVEL_KIT_VERSION}.tar.gz -O ${NGINX_DEVEL_KIT}.tar.gz \
  && tar zxf ${NGINX_DEVEL_KIT}.tar.gz \
  && rm ${NGINX_DEVEL_KIT}.tar.gz

# Get lua-nginx-module.
RUN cd /tmp \
  && wget https://github.com/openresty/lua-nginx-module/archive/v${LUA_NGINX_MODULE_VERSION}.tar.gz -O ${LUA_NGINX_MODULE}.tar.gz \
  && tar zxf ${LUA_NGINX_MODULE}.tar.gz \
  && rm ${LUA_NGINX_MODULE}.tar.gz

# patch nginx lua compilation error on nginx 1.13 (https://github.com/openresty/lua-nginx-module/issues/1016)
ADD ./patch/patch-src-ngx_http_lua_headers.c.diff /tmp/
RUN cd /tmp/${LUA_NGINX_MODULE}/src \
  && patch < /tmp/patch-src-ngx_http_lua_headers.c.diff

# Compile nginx with nginx-rtmp module.
RUN cd /tmp/nginx-${NGINX_VERSION} \
  && ./configure \
  --prefix=/opt/nginx \
  --add-module=/tmp/nginx-rtmp-module-${NGINX_RTMP_VERSION} \
  --with-ld-opt="-Wl,-rpath,${LUAJIT_LIB}" \
  --add-module=/tmp/${NGINX_DEVEL_KIT} \
  --add-module=/tmp/${LUA_NGINX_MODULE} \
  --conf-path=/opt/nginx/nginx.conf --error-log-path=/opt/nginx/logs/error.log --http-log-path=/opt/nginx/logs/access.log \
  --with-debug \
  --with-http_auth_request_module
RUN cd /tmp/nginx-${NGINX_VERSION} && make && make install

# ffmpeg dependencies.
RUN apk add --update --virtual .ffmpeg-dependencies ${DEPS_FFMPEG}

RUN echo http://dl-cdn.alpinelinux.org/alpine/edge/testing >> /etc/apk/repositories
RUN apk add --update fdk-aac-dev

# Get ffmpeg source.
RUN cd /tmp/ && wget http://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz \
  && tar zxf ffmpeg-${FFMPEG_VERSION}.tar.gz && rm ffmpeg-${FFMPEG_VERSION}.tar.gz

# Compile ffmpeg.
RUN cd /tmp/ffmpeg-${FFMPEG_VERSION} && \
  ./configure \
  --enable-version3 \
  --enable-gpl \
  --enable-nonfree \
  --enable-small \
  --enable-libmp3lame \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libvpx \
  --enable-libtheora \
  --enable-libvorbis \
  --enable-libopus \
  --enable-libfdk-aac \
  --enable-libass \
  --enable-libwebp \
  --enable-librtmp \
  --enable-postproc \
  --enable-avresample \
  --enable-libfreetype \
  --enable-openssl \
  --enable-avfilter \
  --enable-libxvid \
  --enable-libv4l2 \
  --enable-pic \
  --enable-shared \
  --enable-vaapi \
  --enable-pthreads \
  --enable-shared \
  --disable-stripping \
  --disable-static \
  --disable-debug
RUN cd /tmp/ffmpeg-${FFMPEG_VERSION} && make && make install && make distclean

# Remove unneccessary dependencies
#RUN apk del .ffmpeg-dependencies .build-dependencies
#RUN apk del ${DEPS_FFMPEG} ${DEPS_NGINX}

# Cleanup.
RUN rm -rf /var/cache/* /tmp/*

# Adding nginx configuration file
ADD nginx.conf /opt/nginx/nginx.conf

# Prepare data directory
RUN mkdir -p /data
RUN mkdir -p /data/hls
RUN mkdir -p /data/dash

# Prepare www directory
RUN mkdir -p /www

# Add static files
ADD static /www/static

# Expose RTMP port
EXPOSE 1935

# Expose HTTP port
EXPOSE 80

# Start NGINX
CMD ["/opt/nginx/sbin/nginx"]
