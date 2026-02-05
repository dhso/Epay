# Docker Run 部署指南

本指南说明如何使用 `docker run` 运行Epay PHP应用，连接到已有的MySQL和Nginx服务。

## 架构说明

```
外部Nginx (负载均衡/反向代理)
    ↓ FastCGI
Epay PHP-FPM容器 (端口9000)
    ↓ MySQL连接
外部MySQL服务
```

所有服务通过Docker网络互联。

## 构建镜像

```bash
cd /Users/donghao/Code/my/Epay
docker build -t epay:latest .
```

查看镜像大小（预计 < 150MB）：
```bash
docker images epay:latest
```

## 运行容器

### 开发环境运行（挂载代码卷）

```bash
docker run -d \
  --name epay \
  --network your-network-name \
  -v /Users/donghao/Code/my/Epay:/var/www/html \
  -e TZ=Asia/Shanghai \
  epay:latest
```

### 生产环境运行（推荐）

```bash
docker run -d \
  --name epay \
  --network your-network-name \
  --restart unless-stopped \
  -e TZ=Asia/Shanghai \
  epay:latest
```

### 参数说明

- `--name epay` - 容器名称
- `--network your-network-name` - 加入已有的Docker网络（与MySQL和Nginx在同一网络）
- `-v /Users/donghao/Code/my/Epay:/var/www/html` - 挂载代码目录（可选，仅用于开发环境）
- `-e TZ=Asia/Shanghai` - 设置时区
- `--restart unless-stopped` - 自动重启策略

## 网络配置

### 1. 查看现有网络

```bash
docker network ls
```

### 2. 创建网络（如果没有）

```bash
docker network create epay-network
```

### 3. 将MySQL和Nginx容器加入网络

```bash
# 假设MySQL容器名为 mysql
docker network connect epay-network mysql

# 假设Nginx容器名为 nginx
docker network connect epay-network nginx
```

## 配置PHP应用连接MySQL

修改项目中的 `config.php`：

```php
$dbhost = 'mysql';  // 使用MySQL容器的名称或服务名
$dbport = 3306;
$dbuser = 'your_db_user';
$dbpwd = 'your_db_password';
$dbname = 'epay';
```

**重要**：`$dbhost` 应该设置为MySQL容器的名称或在Docker网络中的服务名。

## 配置外部Nginx连接PHP-FPM

在外部Nginx配置中添加：

```nginx
server {
    listen 80;
    server_name your-domain.com;
    root /var/www/html;
    index index.php index.html;

    # 访问日志
    access_log /var/log/nginx/epay_access.log;
    error_log /var/log/nginx/epay_error.log;

    client_max_body_size 20M;

    # 静态文件缓存
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # URL重写规则
    location / {
        if (!-e $request_filename) {
            rewrite ^/(.[a-zA-Z0-9\-\_]+).html$ /index.php?mod=$1 last;
        }
        rewrite ^/pay/(.*)$ /pay.php?s=$1 last;
        rewrite ^/api/(.*)$ /api.php?s=$1 last;
        rewrite ^/doc/(.[a-zA-Z0-9\-\_]+).html$ /index.php?doc=$1 last;

        try_files $uri $uri/ /index.php?$query_string;
    }

    # 禁止访问敏感目录
    location ^~ /plugins {
        deny all;
        return 404;
    }

    location ^~ /includes {
        deny all;
        return 404;
    }

    location ~ /\. {
        deny all;
        return 404;
    }

    # PHP-FPM配置 - 关键部分
    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass epay:9000;  # 使用Epay容器名称:端口
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
        
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
    }
}
```

**关键配置**：
- `fastcgi_pass epay:9000;` - 使用Epay容器名称，Docker网络会自动解析
- `root /var/www/html;` - 必须与容器内的路径一致

### Nginx配置文件位置

如果Nginx也在Docker容器中，需要：

1. **挂载代码目录**（Nginx和PHP-FPM看到相同的文件）：
```bash
docker run -d \
  --name nginx \
  --network epay-network \
  -p 80:80 \
  -v /Users/donghao/Code/my/Epay:/var/www/html:ro \
  -v /path/to/nginx.conf:/etc/nginx/conf.d/default.conf:ro \
  nginx:alpine
```

2. **确保网络互通**：
```bash
# Nginx容器能ping通PHP-FPM容器
docker exec nginx ping epay
```

## 常用命令

```bash
# 查看运行状态和健康检查
docker ps -a | grep epay
# STATUS列会显示 "healthy" 或 "unhealthy"

# 查看日志
docker logs -f epay

# 进入容器
docker exec -it epay sh

# 重启容器
docker restart epay

# 停止容器
docker stop epay

# 删除容器
docker rm epay

# 查看容器IP
docker inspect epay | grep IPAddress

# 测试PHP-FPM
docker exec epay php-fpm -t

# 查看健康检查历史
docker inspect epay --format='{{json .State.Health}}' | jq
```

## 更新应用

### 方法1：重新构建镜像（推荐生产环境）

```bash
# 1. 停止并删除旧容器
docker stop epay && docker rm epay

# 2. 重新构建镜像
docker build -t epay:latest .

# 3. 启动新容器
docker run -d \
  --name epay \
  --network epay-network \
  --restart unless-stopped \
  -e TZ=Asia/Shanghai \
  epay:latest
```

### 方法2：使用挂载卷（开发环境）

如果使用了 `-v` 挂载代码：
```bash
# 代码更新后，重启容器即可
docker restart epay
```

## 多实例部署（负载均衡）

启动多个Epay容器：

```bash
# 实例1
docker run -d \
  --name epay-1 \
  --network epay-network \
  --restart unless-stopped \
  epay:latest

# 实例2
docker run -d \
  --name epay-2 \
  --network epay-network \
  --restart unless-stopped \
  epay:latest

# 实例3
docker run -d \
  --name epay-3 \
  --network epay-network \
  --restart unless-stopped \
  epay:latest
```

在Nginx中配置upstream负载均衡：

```nginx
upstream epay_backend {
    server epay-1:9000;
    server epay-2:9000;
    server epay-3:9000;
}

server {
    # ... 其他配置 ...
    
    location ~ \.php$ {
        fastcgi_pass epay_backend;  # 使用upstream
        # ... 其他fastcgi配置 ...
    }
}
```

## 故障排查

### 1. PHP-FPM无法连接

```bash
# 检查容器是否运行
docker ps | grep epay

# 检查网络
docker network inspect epay-network

# 从Nginx容器测试连接
docker exec nginx ping epay
docker exec nginx telnet epay 9000
```

### 2. 数据库连接失败

```bash
# 从Epay容器测试MySQL连接
docker exec epay ping mysql
docker exec epay telnet mysql 3306
```

### 3. 权限问题

```bash
# 检查文件权限
docker exec epay ls -la /var/www/html

# 修复权限（通常不需要，镜像已自动设置）
docker exec epay chown -R www-data:www-data /var/www/html
```

## 环境变量配置（可选）

可以通过环境变量动态配置：

```bash
docker run -d \
  --name epay \
  --network epay-network \
  -e DB_HOST=mysql \
  -e DB_PORT=3306 \
  -e DB_USER=epay_user \
  -e DB_PASS=epay_password \
  -e DB_NAME=epay \
  -e TZ=Asia/Shanghai \
  epay:latest
```

然后在 `config.php` 中使用环境变量：
```php
$dbhost = getenv('DB_HOST') ?: 'localhost';
$dbport = getenv('DB_PORT') ?: 3306;
$dbuser = getenv('DB_USER') ?: 'root';
$dbpwd = getenv('DB_PASS') ?: '';
$dbname = getenv('DB_NAME') ?: 'epay';
```
