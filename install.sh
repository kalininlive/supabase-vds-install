#!/usr/bin/env bash

set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"
}

log "INFO" "🚀 Запуск установки Supabase..."

read -p "Введите домен (например: supabase.example.com): " DOMAIN
read -p "Введите email для SSL и уведомлений: " EMAIL
read -p "Введите логин для Supabase Studio: " DASHBOARD_USERNAME
read -s -p "Придумайте пароль для доступа (будет использован и для Studio и для Basic Auth): " DASHBOARD_PASSWORD
echo ""

log "INFO" "📦 Установка зависимостей..."
apt update
apt install -y ca-certificates curl gnupg lsb-release git unzip jq

if ! command -v docker &> /dev/null; then
  log "INFO" "📥 Установка Docker..."
  curl -fsSL https://get.docker.com | sh
fi

if ! command -v docker compose &> /dev/null; then
  log "INFO" "📥 Установка Docker Compose Plugin..."
  mkdir -p ~/.docker/cli-plugins
  curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
  chmod +x ~/.docker/cli-plugins/docker-compose
fi

log "INFO" "🔑 Генерация переменных..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SITE_URL="https://$DOMAIN"

INSTALL_PATH="/opt/supabase-project"
DOCKER_PATH="$INSTALL_PATH/docker"

log "INFO" "📁 Создание рабочей директории..."
mkdir -p "$INSTALL_PATH"
cd "$INSTALL_PATH"

log "INFO" "⬇️ Скачивание Supabase..."
git clone https://github.com/supabase/supabase.git docker

log "INFO" "🧾 Генерация .env..."
cat > "$DOCKER_PATH/.env" <<EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
SITE_URL=$SITE_URL
SUPABASE_PUBLIC_URL=$SITE_URL
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASS=
SMTP_ADMIN_EMAIL=$EMAIL
SMTP_SENDER_NAME=Supabase
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD
EOF

log "INFO" "🚀 Автозапуск Supabase..."
cd "$DOCKER_PATH"
docker compose --env-file .env up -d

log "INFO" "✅ Установка завершена. Перейдите по ссылке: $SITE_URL"
