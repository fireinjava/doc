#!/bin/bash

# 检查是否提供域名
if [ -z "$1" ]; then
  echo "使用方法: $0 yourdomain.com"
  exit 1
fi

# 接收域名参数
DOMAIN=$1
WWW_DOMAIN="www.$DOMAIN"
CONF_FILE="/etc/nginx/conf.d/$DOMAIN.conf"

mkdir /usr/share/nginx/html_$WWW_DOMAIN

# 检查是否已经存在同名配置文件
if [ -f "$CONF_FILE" ]; then
  echo "配置文件 $CONF_FILE 已存在，请检查。"
  exit 1
fi

# 生成 Nginx 配置内容
cat <<EOL > "$CONF_FILE"
server {
    listen 80;
    server_name $DOMAIN $WWW_DOMAIN;

    root /usr/share/nginx/html_$WWW_DOMAIN;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOL

# 输出结果
echo "已生成 Nginx 配置文件: $CONF_FILE"
echo "请确保 /var/www/html 目录存在并包含 index.html 文件。"

# 测试 Nginx 配置
echo "测试 Nginx 配置..."
sudo nginx -t

if [ $? -eq 0 ]; then
  echo "Nginx 配置测试成功！重新加载服务中..."
  sudo systemctl reload nginx
  echo "Nginx 已重新加载，$DOMAIN 配置完成。"
else
  echo "Nginx 配置测试失败，请检查 $CONF_FILE 文件。"
fi
