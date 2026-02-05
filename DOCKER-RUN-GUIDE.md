# Docker Run 部署指南

本指南说明如何使用 `docker run` 运行Epay PHP应用，连接到已有的MySQL和Nginx服务。

## 架构说明

```
外部Nginx (反向代理)
    ↓ HTTP (端口80/443)
Epay容器 (端口80)
    ├─ Nginx (处理静态文件和URL重写)
    └─ PHP-FPM (处理PHP请求)
        ↓ MySQL连接
外部MySQL服务
```

所有服务通过Docker网络互联。容器内部使用 Supervisor 管理 Nginx 和 PHP-FPM 两个进程。

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
  -p 8080:80 \
  -v /Users/donghao/Code/my/Epay:/var/www/html \
  -e TZ=Asia/Shanghai \
  epay:latest
```

### 生产环境运行（推荐）

```bash
docker run -d \
  --name epay \
  --network your-network-name \
  -p 8080:80 \
  --restart unless-stopped \
  -e TZ=Asia/Shanghai \
  epay:latest
```

### 参数说明

- `--name epay` - 容器名称
- `--network your-network-name` - 加入已有的Docker网络（与MySQL在同一网络）
- `-p 8080:80` - 端口映射（主机端口8080映射到容器端口80）
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

## 配置外部Nginx（反向代理）

外部 Nginx 现在只需要简单的反向代理配置，不需要挂载代码目录或了解应用的 URL 重写规则。

### 基础反向代理配置

```nginx
server {
    listen 80;
    server_name your-domain.com;

    # 访问日志
    access_log /var/log/nginx/epay_access.log;
    error_log /var/log/nginx/epay_error.log;

    # 反向代理到Epay容器
    location / {
        proxy_pass http://epay;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # 超时设置
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        proxy_read_timeout 300;
        
        # 缓冲设置
        proxy_buffering on;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }
}
```

### 负载均衡配置（多实例部署）

```nginx
upstream epay_backend {
    server epay-1:80;
    server epay-2:80;
    server epay-3:80;
}

server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://epay_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### HTTPS配置示例

```nginx
server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://epay;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}
```

**关键配置说明**：
- `proxy_pass http://epay;` - 使用容器名称，Docker网络会自动解析
- 不需要挂载 `/var/www/html` 目录
- 不需要配置 FastCGI 或 URL 重写规则
- 静态文件、URL 重写等都由容器内部的 Nginx 处理

### 外部Nginx配置文件位置

如果外部Nginx也在Docker容器中运行：

```bash
docker run -d \
  --name nginx \
  --network epay-network \
  -p 80:80 \
  -p 443:443 \
  -v /path/to/nginx.conf:/etc/nginx/conf.d/default.conf:ro \
  -v /path/to/ssl:/etc/nginx/ssl:ro \
  nginx:alpine
```

**注意**：不再需要挂载 `/var/www/html` 目录到外部 Nginx！

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

# 测试HTTP访问
curl -I http://localhost:8080/

# 查看容器内进程
docker exec epay ps aux

# 查看nginx和php-fpm状态
docker exec epay supervisorctl status

# 重启nginx或php-fpm
docker exec epay supervisorctl restart nginx
docker exec epay supervisorctl restart php-fpm

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

在外部Nginx中配置upstream负载均衡（参见上方"负载均衡配置"部分）。

## 故障排查

### 1. HTTP连接问题

```bash
# 检查容器是否运行
docker ps | grep epay

# 检查容器日志
docker logs epay

# 检查nginx和php-fpm进程
docker exec epay ps aux | grep -E 'nginx|php-fpm'

# 检查supervisor状态
docker exec epay supervisorctl status

# 从外部Nginx容器测试连接
docker exec nginx ping epay
docker exec nginx curl -I http://epay/

# 直接访问容器（如果有端口映射）
curl -I http://localhost:8080/
```

### 2. 数据库连接失败

```bash
# 从Epay容器测试MySQL连接
docker exec epay ping mysql
docker exec epay nc -zv mysql 3306
```

### 3. Nginx或PHP-FPM进程问题

```bash
# 查看supervisor日志
docker exec epay tail -f /var/log/supervisor/supervisord.log

# 重启特定进程
docker exec epay supervisorctl restart nginx
docker exec epay supervisorctl restart php-fpm

# 测试nginx配置
docker exec epay nginx -t

# 测试php-fpm配置
docker exec epay php-fpm -t
```

### 4. 权限问题

```bash
# 检查文件权限
docker exec epay ls -la /var/www/html

# 修复权限（如需要）
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
