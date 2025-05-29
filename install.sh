#!/usr/bin/env bash

set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"
}

log "INFO" "Запуск установки Supabase..."

read -p "Введите домен (например: supabase.example.com): " DOMAIN
read -p "Введите email для SSL сертификата и уведомлений: " EMAIL
read -p "Введите логин для Supabase Studio: " DASHBOARD_USERNAME
read -s -p "Введите пароль для Supabase Studio и nginx Basic Auth: " DASHBOARD_PASSWORD
echo ""

log "INFO" "Генерация секретных ключей..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SITE_URL="https://$DOMAIN"

log "INFO" "Установка зависимостей..."
apt update -y && apt install -y \
  curl git ca-certificates gnupg lsb-release \
  docker.io nginx certbot python3-certbot-nginx apache2-utils

log "INFO" "Установка Supabase CLI..."
CLI_URL="https://github.com/supabase/cli/releases/latest/download/supabase_Linux_x86_64.tar.gz"
curl -sL "$CLI_URL" | tar xz -C /usr/local/bin supabase
chmod +x /usr/local/bin/supabase

log "INFO" "Запускаем Supabase (supabase start)..."
mkdir -p /opt/supabase
cd /opt/supabase
supabase start

log "INFO" "Создаем файл с переменными окружения..."
cat > .env <<EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD
SITE_URL=$SITE_URL
DOMAIN=$DOMAIN
EOF

log "INFO" "Настраиваем nginx и Basic Auth..."
htpasswd -cb /etc/nginx/.htpasswd "$DASHBOARD_USERNAME" "$DASHBOARD_PASSWORD"

cat > /etc/nginx/sites-available/supabase <<EOF
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

log "INFO" "Получаем SSL сертификат..."
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" || log "WARN" "Не удалось получить сертификат (лимит Let's Encrypt?)"

log "INFO" "Установка завершена. Важные данные:"

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
