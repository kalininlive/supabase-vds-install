#!/usr/bin/env bash

set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# ===== Ввод пользовательских данных =====
read -p "Введите домен (например supabase.example.com): " DOMAIN
read -p "Введите email для SSL и уведомлений: " EMAIL
read -p "Введите логин для Supabase Studio (по умолчанию: supabase): " DASHBOARD_USERNAME
read -s -p "Введите пароль для Supabase Studio (Enter — сгенерируем): " DASHBOARD_PASSWORD
echo ""
read -s -p "Введите пароль для базы данных Postgres (Enter — сгенерируем): " POSTGRES_PASSWORD
echo ""

# ===== Генерация значений по умолчанию, если не введены =====
DASHBOARD_USERNAME=${DASHBOARD_USERNAME:-supabase}
DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD:-$(openssl rand -hex 8)}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$(openssl rand -hex 12)}
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SITE_URL="https://$DOMAIN"

# ===== Установка зависимостей =====
log "Обновление системы и установка зависимостей..."
apt update -y && apt upgrade -y
apt install -y curl git ca-certificates gnupg lsb-release \
  docker.io docker-compose nginx certbot python3-certbot-nginx \
  apache2-utils ufw

systemctl enable docker

# ===== Настройка UFW =====
log "Настройка firewall..."
ufw allow OpenSSH
ufw allow http
ufw allow https
ufw --force enable

# ===== Создание каталога и клонирование Supabase =====
log "Скачивание Supabase..."
mkdir -p /opt/supabase-project
cd /opt/supabase-project

git clone --depth 1 https://github.com/supabase/supabase.git
cp -r supabase/docker/* .
rm -rf supabase

cp .env.example .env

# ===== Заполнение .env =====
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" .env
sed -i "s/^JWT_SECRET=.*/JWT_SECRET=$JWT_SECRET/" .env
sed -i "s/^ANON_KEY=.*/ANON_KEY=$ANON_KEY/" .env
sed -i "s/^SERVICE_ROLE_KEY=.*/SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY/" .env
sed -i "s/^DASHBOARD_USERNAME=.*/DASHBOARD_USERNAME=$DASHBOARD_USERNAME/" .env
sed -i "s/^DASHBOARD_PASSWORD=.*/DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD/" .env
sed -i "s|^SITE_URL=.*|SITE_URL=$SITE_URL|" .env

# Автозапуск контейнеров
sed -i -E '/^  [a-zA-Z0-9_-]+:$/a \    restart: always' docker-compose.yml

# ===== Запуск Supabase =====
log "Запуск Supabase..."
docker compose pull
docker compose up -d

# ===== Настройка NGINX + Basic Auth =====
log "Настройка Nginx + Basic Auth..."
htpasswd -cb /etc/nginx/.htpasswd "$DASHBOARD_USERNAME" "$DASHBOARD_PASSWORD"

cat > /etc/nginx/sites-available/supabase <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        auth_basic "Restricted";
        auth_basic_user_file /etc/nginx/.htpasswd;
        proxy_pass http://localhost:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/supabase
nginx -t && systemctl reload nginx

# ===== Получение SSL сертификата =====
log "Запрос SSL сертификата..."
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" || log "[WARN] Не удалось получить SSL"

# ===== Вывод данных =====
log "Установка завершена. Вот ваши данные:"
echo "=============================================="
echo "URL панели:       $SITE_URL"
echo "Логин:            $DASHBOARD_USERNAME"
echo "Пароль:           $DASHBOARD_PASSWORD"
echo "Postgres пароль:   $POSTGRES_PASSWORD"
echo "JWT_SECRET:       $JWT_SECRET"
echo "Anon key:         $ANON_KEY"
echo "Service key:      $SERVICE_ROLE_KEY"
echo "=============================================="
