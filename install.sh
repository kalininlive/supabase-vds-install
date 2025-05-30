#!/usr/bin/env bash

set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"
}

log "INFO" "🚀 Запуск установки Supabase..."

read -p "Введите домен (например: supabase.example.com): " DOMAIN
read -p "Введите email для SSL сертификата и уведомлений: " EMAIL
read -p "Введите логин для Supabase Studio: " DASHBOARD_USERNAME
read -s -p "Введите пароль для Supabase Studio и nginx Basic Auth: " DASHBOARD_PASSWORD
echo ""

INSTALL_DIR="/opt/supabase-project"
REPO_URL="https://github.com/supabase/supabase"

log "INFO" "📦 Установка Docker и Docker Compose..."
apt update -y
apt install -y ca-certificates curl gnupg lsb-release

mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update -y
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin apache2-utils git nginx

log "INFO" "🔐 Генерация секретных ключей..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SITE_URL="https://$DOMAIN"
SUPABASE_PUBLIC_URL="$SITE_URL"
HASHED_PASSWORD=$(htpasswd -nbB "$DASHBOARD_USERNAME" "$DASHBOARD_PASSWORD" | cut -d ":" -f2)

log "INFO" "📁 Клонирование репозитория Supabase..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"

log "INFO" "📝 Создание .env файла..."
cat > "$INSTALL_DIR/.env" <<EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
SITE_URL=$SITE_URL
SUPABASE_PUBLIC_URL=$SUPABASE_PUBLIC_URL
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$HASHED_PASSWORD
DOCKER_SOCKET_LOCATION=/var/run/docker.sock
EOF

log "INFO" "🌐 Настройка Nginx и SSL..."
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

cat > /etc/nginx/sites-available/supabase <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;
}
EOF

ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/supabase

echo "$DASHBOARD_USERNAME:$HASHED_PASSWORD" > /etc/nginx/.htpasswd
systemctl enable nginx
systemctl restart nginx

log "INFO" "📦 Запуск Supabase через Docker Compose..."
cd "$INSTALL_DIR"
docker compose -f docker/docker-compose.yml --env-file .env up -d

log "INFO" "✅ Установка завершена. Supabase доступен по адресу: $SITE_URL"
