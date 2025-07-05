#!/usr/bin/env bash

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" >&2
  exit 1
fi

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"
}

log "INFO" "\U0001F680 Запуск установки Supabase..."

# Сбор пользовательских данных
read -p "Введите домен (например: supabase.example.com): " DOMAIN
read -p "Введите email для SSL сертификата и уведомлений: " EMAIL
read -p "Введите логин для Supabase Studio: " DASHBOARD_USERNAME
read -s -p "Введите пароль для Supabase Studio и nginx Basic Auth: " DASHBOARD_PASSWORD
echo ""

# Генерация ключей
log "INFO" "\U0001F512 Генерация секретных ключей..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SITE_URL="https://$DOMAIN"

# Установка Docker и зависимостей
log "INFO" "\U0001F6E1 Установка зависимостей..."
apt update && apt install -y \
  ca-certificates curl gnupg lsb-release \
  git jq htop net-tools ufw unzip \
  nginx apache2-utils certbot python3-certbot-nginx

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

ARCH="$(dpkg --print-architecture)"
RELEASE="$(. /etc/os-release && echo "$VERSION_CODENAME")"
echo \
  "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $RELEASE stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# Настройка файрвола
log "INFO" "\U0001F6E1 Настройка UFW..."
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable

# Проверка docker compose
log "INFO" "\U0001F6E1️ Проверка docker compose..."
docker compose version

# Подготовка директорий
log "INFO" "\U0001F4C1 Подготовка директорий..."
mkdir -p /opt/supabase /opt/supabase-project

# Настройка Nginx и Basic Auth
log "INFO" "\U0001F4BB Настройка nginx..."
htpasswd -bc /etc/nginx/.htpasswd "$DASHBOARD_USERNAME" "$DASHBOARD_PASSWORD"
cat <<'NGINXCONF' >/etc/nginx/sites-available/supabase
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        auth_basic "Restricted";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}
NGINXCONF
ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/supabase
nginx -t && systemctl reload nginx
certbot --nginx -d "$DOMAIN" -m "$EMAIL" --agree-tos -n

# Клонирование Supabase (sparse clone)
log "INFO" "⬇️ Клонирование репозитория Supabase..."
git clone --depth=1 --filter=blob:none --sparse https://github.com/supabase/supabase.git /opt/supabase
cd /opt/supabase

# Sparse checkout только docker
git sparse-checkout init --cone
git sparse-checkout set docker

cp -r /opt/supabase/docker/* /opt/supabase-project/
cd /opt/supabase-project

# Запись .env
log "INFO" "✍️ Запись .env..."
cat <<EOF > /opt/supabase-project/.env
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
SITE_URL=$SITE_URL
STUDIO_PASSWORD=$DASHBOARD_PASSWORD
STUDIO_USERNAME=$DASHBOARD_USERNAME
SMTP_ADMIN_EMAIL=$EMAIL
SMTP_HOST=
SMTP_PORT=
DOCKER_SOCKET_LOCATION=/var/run/docker.sock
EOF

# Запуск Supabase контейнеров
log "INFO" "🐳 Запуск Supabase контейнеров..."
cd /opt/supabase-project
docker compose up -d
log "INFO" "✅ Установка завершена! Supabase доступен по адресу $SITE_URL"
