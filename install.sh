#!/bin/bash

set -e

echo "🔹 Введите домен, на котором будет доступен Supabase (например: supabase.example.com):"
read DOMAIN

echo "🔹 Введите логин для доступа к Supabase Studio:"
read -p "Логин: " ADMIN_LOGIN
read -s -p "Пароль: " ADMIN_PASS
echo

echo "🔧 Обновляем пакеты и устанавливаем зависимости..."
apt update && apt install -y \
  curl gnupg2 ca-certificates lsb-release \
  docker.io docker-compose-plugin \
  nginx certbot python3-certbot-nginx \
  apache2-utils ufw git jq htop net-tools

mkdir -p /opt/supabase && cd /opt/supabase

echo "🔐 Настраиваем basic auth..."
htpasswd -cb /etc/nginx/.htpasswd "$ADMIN_LOGIN" "$ADMIN_PASS"

echo "📦 Скачиваем Supabase self-hosted..."
git clone https://github.com/supabase/supabase.git --depth=1
cp -r supabase/docker .

echo "🧪 Создаём .env файл..."
cat <<EOF > .env
SUPABASE_DB_PASSWORD=$(openssl rand -hex 16)
EOF

echo "⚙️ Копируем docker-compose.yml..."
cp docker/docker-compose.yml .

echo "🌐 Настраиваем nginx..."
cat <<EOF > /etc/nginx/sites-available/supabase
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        auth_basic "Restricted";
        auth_basic_user_file /etc/nginx/.htpasswd;
        proxy_pass http://localhost:54323;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/supabase

echo "📡 Проверка nginx конфигурации..."
nginx -t && systemctl reload nginx

echo "🔒 Получаем SSL-сертификат через Let's Encrypt..."
certbot --nginx -d "$DOMAIN"

echo "🚀 Запускаем Supabase..."
docker compose up -d

echo "✅ Готово! Supabase доступен по адресу: https://$DOMAIN"
