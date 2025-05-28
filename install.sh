#!/usr/bin/env bash

set -e

echo "🔹 Введите домен (например: supabase.example.com):"
read DOMAIN

echo "🔹 Введите логин для Supabase Studio:"
read -p "Логин: " DASHBOARD_USERNAME
read -s -p "Пароль: " DASHBOARD_PASSWORD
echo -e "\n🔐 Генерация секретов..."

POSTGRES_PASSWORD=$(openssl rand -hex 16)
SUPABASE_DB_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SITE_URL="https://$DOMAIN"

# Установка зависимостей
apt update && apt install -y curl git docker.io docker-compose nginx certbot python3-certbot-nginx apache2-utils

# Настройка Docker
systemctl enable docker --now

# Загрузка и подготовка Supabase
mkdir -p /opt/supabase && cd /opt/supabase
git clone https://github.com/supabase/supabase.git --depth=1
cp -r supabase/docker ./
cp docker/docker-compose.yml ./

# Фикс монтирования docker.sock
sed -i 's|:/var/run/docker.sock:ro,z|/var/run/docker.sock:/var/run/docker.sock:ro,z|' docker/docker-compose.yml

# Создание .env
cat <<EOF > .env
SUPABASE_DB_PASSWORD=$SUPABASE_DB_PASSWORD
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD
SITE_URL=$SITE_URL
DOMAIN=$DOMAIN
POSTGRES_DB=postgres
POSTGRES_PORT=5432
POSTGRES_HOST=db
EOF

# NGINX + Basic Auth
htpasswd -cb /etc/nginx/.htpasswd "$DASHBOARD_USERNAME" "$DASHBOARD_PASSWORD"

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
nginx -t && systemctl reload nginx

# SSL-сертификат
certbot --nginx -d "$DOMAIN" || echo "⚠️ Не удалось получить сертификат (лимит Let's Encrypt?)"

# Запуск контейнеров
cd /opt/supabase
docker compose --env-file .env -f docker/docker-compose.yml up -d

# Финальный вывод
clear
echo -e "\n✅ Установка завершена. Ниже важные данные:"
echo "----------------------------------------"
echo "Studio URL:         $SITE_URL"
echo "API URL:            $SITE_URL"
echo "DB URL:             postgres://postgres:$POSTGRES_PASSWORD@localhost:5432/postgres"
echo "JWT_SECRET:         $JWT_SECRET"
echo "anon key:           $ANON_KEY"
echo "service_role key:   $SERVICE_ROLE_KEY"
echo "Studio login:       $DASHBOARD_USERNAME"
echo "Studio password:    $DASHBOARD_PASSWORD"
echo "Домен:              $DOMAIN"
echo "----------------------------------------"
