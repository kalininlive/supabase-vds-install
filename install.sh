#!/usr/bin/env bash

set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"
}

log "INFO" "Запуск установки Supabase на Ubuntu 22.04..."

read -p "Введите домен (например: supabase.example.com): " DOMAIN
read -p "Введите email для SSL сертификата и уведомлений: " EMAIL
read -p "Введите логин для Supabase Studio: " DASHBOARD_USERNAME
read -s -p "Введите пароль для Supabase Studio и Basic Auth: " DASHBOARD_PASSWORD

echo ""
log "INFO" "Генерация секретных ключей..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SITE_URL="https://$DOMAIN"
SUPABASE_PUBLIC_URL="$SITE_URL"
DOCKER_SOCKET_LOCATION="/var/run/docker.sock"

log "INFO" "Установка Docker и Docker Compose..."
apt update && apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    nginx \
    apache2-utils \
    unzip \
    ufw

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-ce-rootless-extras docker-buildx-plugin

log "INFO" "Настройка Firewall (UFW)..."
ufw allow ssh
ufw allow http
ufw allow https
ufw --force enable

log "INFO" "Скачивание Supabase..."
mkdir -p /opt/supabase-project && cd /opt/supabase-project
git clone https://github.com/supabase/supabase.git docker

log "INFO" "Создание .env файла..."
HASHED_PASS=$(htpasswd -nbBC 10 "admin" "$DASHBOARD_PASSWORD" | cut -d ":" -f2 | sed 's/\$/\$\$/g')

cat > /opt/supabase-project/.env <<EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
SITE_URL=$SITE_URL
SUPABASE_PUBLIC_URL=$SUPABASE_PUBLIC_URL
DOCKER_SOCKET_LOCATION=$DOCKER_SOCKET_LOCATION
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$HASHED_PASS
EOF

log "INFO" "Настройка Nginx и получение SSL..."
systemctl enable nginx
cat > /etc/nginx/sites-available/supabase <<EOF
server {
  listen 80;
  server_name $DOMAIN;

  location / {
    proxy_pass http://localhost:3000;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;
  }
}
EOF

echo "$DASHBOARD_USERNAME:$(htpasswd -nb "$DASHBOARD_USERNAME" "$DASHBOARD_PASSWORD" | cut -d ":" -f2)" > /etc/nginx/.htpasswd
ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/supabase
nginx -s reload || nginx

log "INFO" "Установка завершена. Для запуска Supabase перейдите в папку: /opt/supabase-project и выполните:"
echo "  docker compose -f docker/docker-compose.yml --env-file .env up -d"
