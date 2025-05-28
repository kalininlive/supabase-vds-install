\#!/bin/bash

set -e

# 🔹 Запрос данных пользователя

echo "🔹 Введите домен, на котором будет доступен Supabase (например: supabase.example.com):"
read DOMAIN

echo "🔹 Введите логин для доступа к Supabase Studio:"
read -p "Логин: " ADMIN\_LOGIN
read -s -p "Пароль: " ADMIN\_PASS
echo

# 🔧 Обновление зеркал и системы

apt update && apt upgrade -y

# 🔧 Установка базовых утилит

apt install -y curl ca-certificates gnupg2 lsb-release software-properties-common

# 🐳 Установка Docker и docker-compose

apt install -y docker.io docker-compose-plugin
systemctl enable docker
systemctl start docker

# 🌐 Установка Nginx, SSL и htpasswd

apt install -y nginx certbot python3-certbot-nginx apache2-utils

# 🛠 Подготовка структуры

mkdir -p /opt/supabase && cd /opt/supabase

echo "🔐 Настраиваем Basic Auth..."
htpasswd -cb /etc/nginx/.htpasswd "\$ADMIN\_LOGIN" "\$ADMIN\_PASS"

echo "📦 Скачиваем Supabase..."
git clone [https://github.com/supabase/supabase.git](https://github.com/supabase/supabase.git) --depth=1
cp -r supabase/docker .

# ⚙️ Настройка .env

cat <<EOF > .env
SUPABASE\_DB\_PASSWORD=\$(openssl rand -hex 16)
EOF

cp docker/docker-compose.yml .

# 🌐 Настройка nginx

cat <<EOF > /etc/nginx/sites-available/supabase
server {
listen 80;
server\_name \$DOMAIN;

```
location / {
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;
    proxy_pass http://localhost:54323;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
}
```

}
EOF

ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/supabase

# 🔍 Проверка и перезапуск Nginx

nginx -t && systemctl reload nginx

# 🔒 Получение сертификата

certbot --nginx -d "\$DOMAIN"

# 🚀 Запуск Supabase

docker compose up -d

echo "✅ Готово! Supabase доступен по адресу: https\://\$DOMAIN"
