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

log "INFO" "📆 Установка Docker и Compose..."
apt update
apt install -y curl ca-certificates gnupg lsb-release apache2-utils
curl -fsSL https://get.docker.com | sh
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \  
  "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  \
  $(lsb_release -cs) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update && apt install -y docker-compose-plugin

log "INFO" "🛡️ Проверка docker-compose..."
docker compose version || { echo "Docker Compose не найден"; exit 1; }

log "INFO" "🔐 Генерация переменных..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SITE_URL="https://$DOMAIN"
SUPABASE_PUBLIC_URL="$SITE_URL"

log "INFO" "📁 Создание рабочей директории..."
INSTALL_DIR="/opt/supabase-project"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

git clone https://github.com/supabase/supabase.git docker

log "INFO" "📂 Запись .env..."
cat <<EOF > "$INSTALL_DIR/.env"
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
SITE_URL=$SITE_URL
SUPABASE_PUBLIC_URL=$SUPABASE_PUBLIC_URL
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$(apr1 hash)
DOCKER_SOCKET_LOCATION=/var/run/docker.sock
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_USER_ID=$TG_USER_ID
EOF

log "INFO" "🚀 Автозапуск Supabase..."
docker compose -f docker/docker-compose.yml --env-file .env up -d || true

log "INFO" "📢 Отчёт в Telegram..."
curl -s -X POST https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage \
    -d chat_id=$TG_USER_ID \
    -d text="🚀 Supabase запущен на $DOMAIN. \nLogin: $DASHBOARD_USERNAME"

log "INFO" "🎉 Установка Supabase завершена!"
exit 0
