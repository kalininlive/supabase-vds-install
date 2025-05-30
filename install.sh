#!/usr/bin/env bash

set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"
}

log "INFO" "🚀 Старт установки Supabase на ваш сервер"

### 1. Запрос переменных у пользователя
read -p "Введите домен (например: supabase.example.com): " DOMAIN
read -p "Введите email для SSL сертификата и уведомлений: " EMAIL
read -p "Введите логин для Supabase Studio: " DASHBOARD_USERNAME
read -s -p "Введите пароль для Supabase Studio и nginx Basic Auth: " DASHBOARD_PASSWORD
echo ""
read -p "Введите Telegram Bot Token: " TG_BOT_TOKEN
read -p "Введите Telegram User ID для уведомлений: " TG_USER_ID

### 2. Установка Docker, если не установлен
if ! command -v docker &> /dev/null; then
  log "INFO" "Установка Docker..."
  apt update
  apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \ 
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \ 
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt update
  apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  log "INFO" "✅ Docker уже установлен"
fi

### 3. Проверка Docker Compose
if ! docker compose version &> /dev/null; then
  log "ERROR" "Docker Compose не установлен или не работает"
  exit 1
fi

log "INFO" "🔐 Генерация ключей..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
KONG_PASSWORD=$(openssl rand -hex 20)
SITE_URL="https://$DOMAIN"

### 4. Подготовка директорий
mkdir -p /opt/supabase /opt/supabase-project
cd /opt/supabase

### 5. Клонирование только нужных папок Supabase
if [ ! -d ".git" ]; then
  log "INFO" "⬇️ Клонирование репозитория Supabase (sparse)..."
  git init
  git remote add origin https://github.com/supabase/supabase.git
  git config core.sparseCheckout true
  echo "docker" >> .git/info/sparse-checkout
  git pull origin master
else
  log "INFO" "✅ Репозиторий уже клонирован"
fi

### 6. Копирование docker-сборки
cp -r docker /opt/supabase-project/
cd /opt/supabase-project

### 7. Создание .env
cat <<EOF > .env
# === USER CONFIG ===
PROJECT_DOMAIN=$DOMAIN
SITE_URL=$SITE_URL
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_USER_ID=$TG_USER_ID

# === DATABASE ===
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# === JWT ===
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY

# === KONG ===
KONG_PASSWORD=$KONG_PASSWORD

# === SMTP ===
SMTP_ADMIN_EMAIL=
SMTP_HOST=
SMTP_PORT=
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_SENDER_NAME=
SMTP_SENDER_EMAIL=

EOF

log "INFO" "📦 Загрузка docker-образов и запуск Supabase..."
docker compose -f docker/docker-compose.yml --env-file .env up -d

log "INFO" "✅ Supabase установлен и запущен. Панель: https://$DOMAIN"
log "INFO" "🔐 Пароль Supabase Studio: $DASHBOARD_PASSWORD"
log "INFO" "📬 Добавь SMTP настройки в .env и перезапусти контейнеры при необходимости"
log "INFO" "👮 Защита обеспечивается Kong: авторизация по паролю и без доступа по IP к PostgreSQL"

exit 0
