#!/usr/bin/env bash

set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"
}

log "INFO" "🚀 Запуск установки Supabase..."

read -p "Введите домен (например: supabase.example.com): " DOMAIN
read -p "Введите email для SSL и уведомлений: " EMAIL
read -p "Введите логин для Supabase Studio: " DASHBOARD_USERNAME
read -s -p "Введите пароль для доступа: " DASHBOARD_PASSWORD
echo ""
read -p "Введите Telegram токен бота: " TG_BOT_TOKEN
read -p "Введите Telegram ID получателя: " TG_USER_ID

log "INFO" "📦 Установка зависимостей..."
apt update
apt install -y curl ca-certificates gnupg lsb-release apache2-utils git
curl -fsSL https://get.docker.com | sh
apt install -y docker-compose-plugin

log "INFO" "🛡️ Проверка docker compose..."
docker compose version || { echo "Docker Compose не найден"; exit 1; }

log "INFO" "🔐 Генерация переменных..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SITE_URL="https://$DOMAIN"
SUPABASE_PUBLIC_URL="$SITE_URL"
SECRET_KEY_BASE=$(openssl rand -hex 64)
VAULT_ENC_KEY=$(openssl rand -hex 32)

log "INFO" "📁 Подготовка директорий..."
cd /opt
rm -rf supabase supabase-project

log "INFO" "⬇️ Клонирование репозитория Supabase..."
git clone --filter=blob:none --no-checkout https://github.com/supabase/supabase
cd supabase
git sparse-checkout init --cone
git sparse-checkout set docker
git checkout master
cd ..

mkdir supabase-project
cp -rf supabase/docker/* supabase-project/
cp supabase/docker/.env.example supabase-project/.env
cd supabase-project

log "INFO" "✍️ Запись .env..."
cat <<EOF > .env
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
SITE_URL=$SITE_URL
SUPABASE_PUBLIC_URL=$SUPABASE_PUBLIC_URL
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$(htpasswd -nbB user "$DASHBOARD_PASSWORD" | cut -d":" -f2)
SECRET_KEY_BASE=$SECRET_KEY_BASE
VAULT_ENC_KEY=$VAULT_ENC_KEY
DOCKER_SOCKET_LOCATION=/var/run/docker.sock
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_USER_ID=$TG_USER_ID
# SMTP настройки оставлены пустыми, см. README
SMTP_ADMIN_EMAIL=
SMTP_HOST=
SMTP_PORT=
SMTP_USER=
SMTP_PASS=
SMTP_SENDER_NAME=
MAILER_URLPATHS_CONFIRMATION=
MAILER_URLPATHS_INVITE=
MAILER_URLPATHS_RECOVERY=
MAILER_URLPATHS_EMAIL_CHANGE=
EOF

log "INFO" "📦 Загрузка docker-образов..."
docker compose pull

log "INFO" "🚀 Запуск Supabase..."
docker compose up -d

log "INFO" "📢 Отправка статуса в Telegram..."
curl -s -X POST https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage \
    -d chat_id=$TG_USER_ID \
    -d text="🚀 Supabase установлен на $DOMAIN"

log "INFO" "✅ Установка завершена!"
exit 0
