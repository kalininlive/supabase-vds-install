#!/usr/bin/env bash

set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"
}

# Проверка и установка Docker при необходимости
if ! command -v docker &> /dev/null; then
  log "INFO" "Установка Docker..."
  apt-get update && \
  apt-get install -y ca-certificates curl gnupg lsb-release && \
  install -m 0755 -d /etc/apt/keyrings && \
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
  echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
  apt-get update && \
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

log "INFO" "🛡️ Проверка docker-compose..."
docker compose version

log "INFO" "🔐 Генерация переменных..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SITE_URL="https://$DOMAIN"
SECRET_KEY_BASE=$(openssl rand -hex 32)

log "INFO" "📁 Подготовка директорий..."
mkdir -p /opt/supabase /opt/supabase-project
cd /opt

log "INFO" "⬇️ Клонирование репозитория Supabase..."
if [ ! -d "supabase" ]; then
  git clone --filter=blob:none --no-checkout https://github.com/supabase/supabase
  cd supabase
  git sparse-checkout init --cone
  git sparse-checkout set docker
  git checkout master
  cd ..
fi

log "INFO" "📂 Копирование docker файлов..."
cp -rf supabase/docker/* supabase-project/
cp supabase/docker/.env.example supabase-project/.env

log "INFO" "✍️ Запись .env..."
cat > /opt/supabase-project/.env <<EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
SECRET_KEY_BASE=$SECRET_KEY_BASE
SITE_URL=$SITE_URL
SMTP_ADMIN_EMAIL=
SMTP_HOST=
SMTP_PORT=
SMTP_USER=
SMTP_PASS=
SMTP_SENDER_NAME=
MAILER_URLPATHS_INVITE=
MAILER_URLPATHS_CONFIRMATION=
MAILER_URLPATHS_RECOVERY=
MAILER_URLPATHS_EMAIL_CHANGE=
API_EXTERNAL_URL=
ENABLE_EMAIL_SIGNUP=true
ENABLE_EMAIL_AUTOCONFIRM=false
ENABLE_PHONE_SIGNUP=false
ENABLE_PHONE_AUTOCONFIRM=false
ENABLE_ANONYMOUS_USERS=false
DISABLE_SIGNUP=false
JWT_EXPIRY=3600
EOF

log "INFO" "📦 Загрузка docker-образов..."
cd /opt/supabase-project
docker compose pull

log "INFO" "🚀 Запуск Supabase..."
docker compose up -d

log "INFO" "✅ Установка завершена. Supabase доступен по адресу: $SITE_URL"

exit 0
