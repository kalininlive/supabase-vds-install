#!/usr/bin/bash

set -e

# 🔹 Ввод переменных пользователем
echo "🔹 Введите домен (например: supabase.example.com):"
read DOMAIN

echo "🔹 Введите логин для Supabase Studio:"
read -p "Логин: " DASHBOARD_USERNAME
read -s -p "Пароль: " DASHBOARD_PASSWORD
echo -e "\n🔐 Генерируем секреты..."

POSTGRES_PASSWORD=$(openssl rand -hex 16)
SUPABASE_DB_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
S3_ACCESS_KEY=$(openssl rand -hex 16)
S3_SECRET_KEY=$(openssl rand -hex 32)
S3_REGION=local

SITE_URL=https://$DOMAIN

# 📦 Установка Docker и Docker Compose
apt update && apt upgrade -y
apt install -y curl git
curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh
apt install -y docker-compose-plugin

# 🔧 Установка утилит
apt install -y ca-certificates gnupg2 lsb-release software-properties-common nginx certbot python3-certbot-nginx apache2-utils

# 🛠 Подготовка Supabase
mkdir -p /opt/supabase && cd /opt/supabase
git clone https://github.com/supabase/supabase.git --depth=1
cp -r supabase/docker .

# 🔐 Настраиваем basic auth
htpasswd -cb /etc/nginx/.htpasswd "$DASHBOARD_USERNAME" "$DASHBOARD_PASSWORD"

# 📝 Сохраняем переменные в .env
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
S3_ACCESS_KEY=$S3_ACCESS_KEY
S3_SECRET_KEY=$S3_SECRET_KEY
S3_REGION=$S3_REGION
EOF

# 🛠 Фикс docker.sock, если нужен
sed -i 's|:/var/run/docker.sock:ro,z|/var/run/docker.sock:/var/run/docker.sock:ro,z|g' docker/docker-compose.yml

cp docker/docker-compose.yml .

# 🌐 Настройка nginx
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

# 🔒 SSL-сертификат
certbot --nginx -d "$DOMAIN"

# 🚀 Запуск Supabase
cd /opt/supabase
docker compose --env-file .env up -d

# 📋 Финальный вывод
clear
echo -e "\n✅ Установка завершена. Ниже важные данные:"
echo "----------------------------------------"
echo "Studio URL:         $SITE_URL"
echo "API URL:            $SITE_URL"
echo "DB:                 postgres://postgres:$POSTGRES_PASSWORD@localhost:5432/postgres"
echo "JWT_SECRET:         $JWT_SECRET"
echo "anon key:           $ANON_KEY"
echo "service_role key:   $SERVICE_ROLE_KEY"
echo "Studio login:       $DASHBOARD_USERNAME"
echo "Studio password:    $DASHBOARD_PASSWORD"
echo "S3 Access Key:      $S3_ACCESS_KEY"
echo "S3 Secret Key:      $S3_SECRET_KEY"
echo "S3 Region:          $S3_REGION"
echo "Домен:              $DOMAIN"
echo "----------------------------------------"
echo -e "\n💡 Эти данные понадобятся тебе для настройки n8n и других сервисов."
