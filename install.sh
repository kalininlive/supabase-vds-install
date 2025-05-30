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
apt update -y
apt install -y curl git openssl apache2-utils docker.io docker-compose-plugin

log "INFO" "📁 Клонирование репозитория Supabase..."
git clone https://github.com/supabase/supabase.git /opt/supabase-project
cd /opt/supabase-project

log "INFO" "🔐 Генерация секретов..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SECRET_KEY_BASE=$(openssl rand -hex 32)
HTPASSWD=$(htpasswd -nbB "$DASHBOARD_USERNAME" "$DASHBOARD_PASSWORD" | sed -E 's/\$/\$\$/g')

log "INFO" "🧬 Создание .env..."
cat <<EOF > .env
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
SITE_URL=https://$DOMAIN
SUPABASE_PUBLIC_URL=https://$DOMAIN
DOCKER_SOCKET_LOCATION=/var/run/docker.sock
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$HTPASSWD
SECRET_KEY_BASE=$SECRET_KEY_BASE

# дополнительные переменные из документации
POSTGRES_DB=postgres
POSTGRES_HOST=db
POSTGRES_PORT=5432
PGRST_DB_SCHEMAS=public
JWT_EXPIRY=3600
ENABLE_EMAIL_SIGNUP=true
ENABLE_EMAIL_AUTOCONFIRM=true
ENABLE_PHONE_SIGNUP=false
ENABLE_PHONE_AUTOCONFIRM=false
ENABLE_ANONYMOUS_USERS=true
DISABLE_SIGNUP=false
SMTP_HOST=mail.example.com
SMTP_PORT=587
SMTP_USER=username
SMTP_PASS=password
SMTP_SENDER_NAME=Supabase
SMTP_ADMIN_EMAIL=admin@example.com
MAILER_URLPATHS_CONFIRMATION=/auth/confirm
MAILER_URLPATHS_RECOVERY=/auth/recover
MAILER_URLPATHS_INVITE=/auth/invite
MAILER_URLPATHS_EMAIL_CHANGE=/auth/email-change
API_EXTERNAL_URL=https://$DOMAIN
IMGPROXY_ENABLE_WEBP_DETECTION=true
FUNCTIONS_VERIFY_JWT=true
VAULT_ENC_KEY=$(openssl rand -hex 32)
POOLER_TENANT_ID=default
POOLER_DEFAULT_POOL_SIZE=10
POOLER_MAX_CLIENT_CONN=100
POOLER_PROXY_PORT_TRANSACTION=5432
LOGFLARE_API_KEY=none
STUDIO_DEFAULT_ORGANIZATION=supabase
STUDIO_DEFAULT_PROJECT=supabase
EOF

log "INFO" "🔧 Запуск Supabase..."
docker compose -f docker/docker-compose.yml --env-file .env up -d

log "SUCCESS" "✅ Supabase успешно установлен и запущен: https://$DOMAIN"
