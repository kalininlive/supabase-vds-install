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

log "INFO" "Установка Docker и Docker Compose..."
apt update
apt install -y ca-certificates curl gnupg lsb-release ufw nginx apache2-utils unzip
curl -fsSL https://get.docker.com | sh
usermod -aG docker ${USER:-root}
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-compose-plugin

log "INFO" "Настройка Firewall (UFW)..."
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable

log "INFO" "Скачивание Supabase..."
cd /opt
rm -rf supabase-project
mkdir -p supabase-project
cd supabase-project
git clone https://github.com/supabase/supabase.git
cp -r supabase/docker .
rm -rf supabase

log "INFO" "Создание .env файла..."
cat <<EOF > .env
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
SITE_URL=$SITE_URL
SUPABASE_PUBLIC_URL=$SITE_URL
DOCKER_SOCKET_LOCATION=/var/run/docker.sock
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$(openssl passwd -apr1 $DASHBOARD_PASSWORD)
EOF

log "INFO" "Настройка Nginx и получение SSL..."
hash nginx || apt install -y nginx
systemctl enable nginx
systemctl start nginx

log "INFO" "Создание nginx site config..."
cat <<EOF > /etc/nginx/sites-available/supabase
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

ln -s /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/
systemctl reload nginx

log "INFO" "Получение сертификата Let's Encrypt..."
apt install -y certbot python3-certbot-nginx
certbot --nginx --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN"

log "INFO" "Запуск Supabase через Docker Compose..."
cd docker
docker compose pull
docker compose up -d

log "INFO" "Supabase успешно установлен!"
log "INFO" "Открой в браузере: https://$DOMAIN"
log "INFO" "Логин: $DASHBOARD_USERNAME"
log "INFO" "Пароль: тот, что ты вводил выше"
log "INFO" "Не забудь сохранить .env и настроить SMTP при необходимости."
