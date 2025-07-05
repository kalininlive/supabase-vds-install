#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" >&2
  exit 1
fi

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"
}

log "INFO" "🚀 Запуск установки Supabase..."

#
# 0) Очистка старых установок
#
rm -rf /opt/supabase /opt/supabase-project

#
# 1) Сбор данных
#
read -p "Введите домен (например: supabase.example.com): " DOMAIN
read -p "Введите email для SSL и уведомлений: " EMAIL
read -p "Введите логин для Supabase Studio: " DASHBOARD_USERNAME
read -s -p "Введите пароль для Supabase Studio/nginx Basic Auth: " DASHBOARD_PASSWORD
echo ""

#
# 2) Генерация секретов
#
log "INFO" "🔑 Генерация ключей..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SITE_URL="https://$DOMAIN"

#
# 3) Установка системных пакетов
#
log "INFO" "📦 Установка зависимостей..."
apt update
apt install -y \
  ca-certificates curl gnupg lsb-release \
  git jq htop net-tools ufw unzip \
  nginx apache2-utils certbot python3-certbot-nginx

#
# 4) Установка Docker и Compose-плагина
#
log "INFO" "🐳 Установка Docker и Compose-плагина..."
apt update
apt install -y docker.io docker-compose-plugin
systemctl enable --now docker

#
# 5) Настройка файрвола
#
log "INFO" "🛡️ Настройка UFW..."
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable

#
# 6) Подготовка директорий
#
log "INFO" "📁 Подготовка директорий..."
mkdir -p /opt/supabase /opt/supabase-project

#
# 7) Настройка nginx + Basic Auth
#
log "INFO" "💻 Настройка nginx..."
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

#
# 8) Настройка HTTPS
#
log "INFO" "🔒 Настройка HTTPS через Certbot..."
certbot --nginx -d "$DOMAIN" -m "$EMAIL" --agree-tos -n

#
# 9) Клонирование Supabase и sparse-checkout
#
log "INFO" "⬇️ Клонирование репозитория Supabase..."
git clone --depth=1 --filter=blob:none --sparse https://github.com/supabase/supabase.git /opt/supabase
cd /opt/supabase
git sparse-checkout init --cone
git sparse-checkout set docker

#
# 10) Копирование Docker-манифестов
#
log "INFO" "📄 Копирование Docker-манифестов..."
cp -r docker/* /opt/supabase-project/

#
# 11) Запись .env
#
log "INFO" "✍️ Запись .env..."
cat <<EOF > /opt/supabase-project/.env
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
SITE_URL=$SITE_URL
SUPABASE_PUBLIC_URL=$SITE_URL
SMTP_ADMIN_EMAIL=$EMAIL
SMTP_HOST=
SMTP_PORT=
DOCKER_SOCKET_LOCATION=/var/run/docker.sock
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD
EOF

#
# 12) Запуск Supabase
#
log "INFO" "🐳 Поднимаем Supabase..."
cd /opt/supabase-project
docker compose up -d --remove-orphans

log "INFO" "✅ Установка завершена! Supabase доступен по адресу $SITE_URL"
