#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"
}

log "INFO" "🚀 Запуск установки Supabase..."

read -p "Введите домен (например: supabase.example.com): " DOMAIN
read -p "Введите email для SSL и уведомлений: " EMAIL
read -p "Придумайте логин для Supabase Studio: " DASHBOARD_USERNAME
read -s -p "Придумайте пароль для доступа (будет использован и для Studio и для Basic Auth): " DASHBOARD_PASSWORD
echo ""

log "INFO" "📦 Установка зависимостей..."
apt update && apt install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  apache2-utils \
  docker.io

log "INFO" "🛠 Установка docker-compose вручную..."
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

log "INFO" "🧪 Проверка docker-compose..."
docker compose version

log "INFO" "🔑 Генерация переменных..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SITE_URL="https://$DOMAIN"

log "INFO" "📁 Создание рабочей директории..."
mkdir -p /opt/supabase-project
cd /opt/supabase-project

log "INFO" "⬇️ Скачивание Supabase..."
git clone --depth 1 https://github.com/supabase/supabase.git docker

log "INFO" "🧾 Генерация .env..."
cat > .env <<EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
SITE_URL=$SITE_URL
SUPABASE_PUBLIC_URL=$SITE_URL
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$(htpasswd -nbB "" "$DASHBOARD_PASSWORD" | cut -d ':' -f2)
DOCKER_SOCKET_LOCATION=/var/run/docker.sock
EOF

log "INFO" "🚀 Автозапуск Supabase..."
docker compose -f docker/docker-compose.yml --env-file .env up -d

log "INFO" "✅ Установка завершена. Доступ: $SITE_URL"
