#!/usr/bin/env bash

set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"
}

log "INFO" "🚀 Запуск установки Supabase..."

read -p "Введите домен (supabase.example.com): " DOMAIN
read -p "Введите email для SSL и уведомлений: " EMAIL
read -p "Придумайте логин для Supabase Studio: " DASHBOARD_USERNAME
read -s -p "Придумайте пароль для доступа: " DASHBOARD_PASSWORD
echo ""
read -p "Токен телеграм-бота: " TG_BOT_TOKEN
read -p "ИД Telegram получателя: " TG_USER_ID

log "INFO" "📦 Установка зависимостей..."
apt update
apt install -y curl ca-certificates gnupg lsb-release apache2-utils git

log "INFO" "🐳 Установка Docker..."
curl -fsSL https://get.docker.com | sh
apt install -y docker-compose-plugin

log "INFO" "🧪 Проверка docker compose..."
docker compose version || { echo "❌ Docker Compose не найден"; exit 1; }

log "INFO" "🔐 Генерация ключей..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SITE_URL="https://$DOMAIN"
SUPABASE_PUBLIC_URL="$SITE_URL"
HASHED_PASSWORD=$(htpasswd -nbB "$DASHBOARD_USERNAME" "$DASHBOARD_PASSWORD" | cut -d ':' -f 2)

log "INFO" "📁 Подготовка директорий..."
mkdir -p /opt && cd /opt
rm -rf supabase supabase-project

log "INFO" "⬇️ Клонирование репозитория Supabase..."
git clone --filter=blob:none --no-checkout https://github.com/supabase/supabase
cd supabase
git sparse-checkout init --cone
git sparse-checkout set docker
git checkout master
cd ..

log "INFO" "📂 Копирование docker файлов..."
cp -rf supabase/docker supabase-project
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
DASHBOARD_PASSWORD=$HASHED_PASSWORD
DOCKER_SOCKET_LOCATION=/var/run/docker.sock
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_USER_ID=$TG_USER_ID
EOF

log "INFO" "📦 Загрузка docker-образов..."
docker compose -f docker/docker-compose.yml --env-file .env pull

log "INFO" "🚀 Запуск Supabase..."
docker compose -f docker/docker-compose.yml --env-file .env up -d

log "INFO" "📤 Уведомление в Telegram..."
curl -s -X POST https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage \
    -d chat_id=$TG_USER_ID \
    -d text="✅ Supabase установлен на $SITE_URL\nLogin: $DASHBOARD_USERNAME"

log "INFO" "🎉 Установка Supabase завершена!"
