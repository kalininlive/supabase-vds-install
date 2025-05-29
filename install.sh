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
SUPABASE_DB_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SITE_URL="https://$DOMAIN"

log "INFO" "Установка зависимостей..."
apt update -y && apt install -y \
  curl git ca-certificates gnupg lsb-release \
  docker.io nginx certbot python3-certbot-nginx apache2-utils

log "INFO" "Установка Docker Compose V2..."
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt update -y
apt install -y docker-compose-plugin docker-buildx-plugin

log "INFO" "Включаем и запускаем Docker..."
systemctl enable docker --now

log "INFO" "Клонируем репозиторий Supabase..."
mkdir -p /opt/supabase
cd /opt/supabase
if [ -d supabase ]; then
  cd supabase
  git fetch --all
  git reset --hard origin/main
  cd ..
  log "INFO" "Обновили репозиторий Supabase"
else
  git clone https://github.com/supabase/supabase.git --depth=1
  log "INFO" "Клонировали репозиторий Supabase"
fi

log "INFO" "Копируем Docker конфигурации..."
cp -r supabase/docker ./docker
cp docker/docker-compose.yml ./

log "INFO" "Настраиваем docker.sock..."
sed -i 's|:/var/run/docker.sock:ro,z|/var/run/docker.sock:/var/run/docker.sock:ro,z|' docker/docker-compose.yml

log "INFO" "Создаём .env файл..."
cat > .env <<EOF
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
certbot --nginx -d "$DOMAIN" || log "WARN" "Не удалось получить сертификат (лимит Let's Encrypt?)"

log "INFO" "Запускаем контейнеры Supabase..."
docker compose --env-file .env -f docker/docker-compose.yml up -d

log "INFO" "Установка завершена. Вот важные данные:"

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
