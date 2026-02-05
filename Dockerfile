# 多阶段构建 - 阶段1: 安装依赖
FROM composer:2 AS builder

# 安装bcmath和gmp扩展（composer依赖需要）
RUN apk add --no-cache gmp gmp-dev \
    && docker-php-ext-install bcmath gmp

WORKDIR /app

# 复制composer配置文件
COPY includes/composer.json /app/includes/composer.json

# 安装PHP依赖（禁用安全审计阻塞）
ENV COMPOSER_ALLOW_SUPERUSER=1
RUN composer config --global audit.abandoned ignore \
    && composer config --global audit.block-insecure false \
    && cd /app/includes && composer install --no-dev --optimize-autoloader --no-interaction

# 阶段2: 生产环境运行时
FROM php:8.1-fpm-alpine

# 安装必需的系统依赖和PHP扩展（合并为单个RUN减少镜像层）
RUN apk add --no-cache \
    freetype \
    libpng \
    libjpeg-turbo \
    libzip \
    oniguruma \
    gmp \
    fcgi \
    && apk add --no-cache --virtual .build-deps \
    freetype-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    libzip-dev \
    oniguruma-dev \
    gmp-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
    mysqli \
    pdo_mysql \
    gd \
    mbstring \
    zip \
    bcmath \
    gmp \
    opcache \
    && apk del .build-deps \
    && rm -rf /var/cache/apk/* /tmp/*

# 配置OPcache优化性能
RUN { \
    echo 'opcache.enable=1'; \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=10000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.validate_timestamps=0'; \
    } > /usr/local/etc/php/conf.d/opcache.ini

# 复制自定义PHP配置
COPY php.ini /usr/local/etc/php/conf.d/custom.ini

# 设置工作目录
WORKDIR /var/www/html

# 从builder阶段复制vendor目录，并设置权限
COPY --from=builder --chown=www-data:www-data /app/includes/vendor /var/www/html/includes/vendor

# 复制应用代码，并设置权限（.dockerignore会自动排除不需要的文件）
COPY --chown=www-data:www-data . /var/www/html

# 暴露PHP-FPM端口
EXPOSE 9000

# 添加健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 || exit 1

# 启动PHP-FPM
CMD ["php-fpm"]
