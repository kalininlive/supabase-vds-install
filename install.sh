#!/usr/bin/env bash

set -euo pipefail

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
apt update && apt install -y ca-certificates curl gnupg lsb-release

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

# Проверка docker compose
log "INFO" "\U0001F6E1️ Проверка docker compose..."
docker compose version

# Подготовка директорий
log "INFO" "\U0001F4C1 Подготовка директорий..."
mkdir -p /opt/supabase /opt/supabase-project

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
cat <<EOF > .env
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
SMTP_USERNAME=
SMTP_PASSWORD=
EOF

# Запуск Supabase
log "INFO" "\U0001F4E6 Загрузка docker-образов..."
docker compose up -d

log "INFO" "✅ Установка завершена! Перейдите по ссылке: https://$DOMAIN"
