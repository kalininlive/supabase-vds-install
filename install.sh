#!/usr/bin/env bash

set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"
}

log "INFO" "🚀 Запуск установки Supabase..."

read -p "Введите домен (например: supabase.example.com): " DOMAIN
read -p "Введите email для SSL сертификата: " EMAIL
read -p "Введите логин для Supabase Studio: " DASHBOARD_USERNAME
read -s -p "Введите пароль для Supabase Studio (и для Basic Auth в Kong): " DASHBOARD_PASSWORD
echo ""
read -p "Введите Telegram Bot Token: " TG_BOT_TOKEN
read -p "Введите Telegram User ID для уведомлений: " TG_USER_ID

log "INFO" "🔐 Генерация переменных..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SITE_URL="https://$DOMAIN"

log "INFO" "📁 Подготовка директорий..."
rm -rf /opt/supabase /opt/supabase-project
mkdir -p /opt/supabase-project
cd /opt

log "INFO" "⬇️ Клонирование репозитория Supabase..."
git clone https://github.com/supabase/supabase.git
cd /opt/supabase
git checkout master

log "INFO" "📂 Копирование docker-файлов..."
cp -rf docker/* /opt/supabase-project/

log "INFO" "✍️ Запись .env..."
cat <<EOF > /opt/supabase-project/.env
# --- Основные ключи ---
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
SITE_URL=$SITE_URL

# --- Supabase Studio ---
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD

# --- SMTP (оставляем пустыми, настраивается вручную) ---
SMTP_HOST=
SMTP_PORT=
SMTP_USER=
SMTP_PASS=
SMTP_ADMIN_EMAIL=
SMTP_SENDER_NAME=

# --- Logflare (опционально, оставим пустым) ---
LOGFLARE_API_KEY=

# --- Telegram уведомления ---
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_USER_ID=$TG_USER_ID
EOF

log "INFO" "📦 Загрузка docker-образов..."
cd /opt/supabase-project
docker compose pull

log "INFO" "🚀 Запуск Supabase..."
docker compose up -d

sleep 5
STATUS=$(docker compose ps | grep -E 'Up|running' | wc -l)

MESSAGE="✅ Supabase установлен на домене: $DOMAIN
📦 Контейнеров запущено: $STATUS
🛡️ Панель Studio: https://$DOMAIN
🔐 Логин: $DASHBOARD_USERNAME"

curl -s -X POST https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage \
  -d chat_id=$TG_USER_ID \
  -d text="$(echo "$MESSAGE")"

log "INFO" "✅ Установка завершена!"
