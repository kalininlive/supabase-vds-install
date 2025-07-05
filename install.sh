#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"
}

if [[ $EUID -ne 0 ]]; then
  log "ERROR" "Этот скрипт нужно запускать от root"
  exit 1
fi

log "INFO" "🚀 Старт установки Supabase..."

#
# 0) Чистка предыдущих установок
#
rm -rf /opt/supabase /opt/supabase-project

#
# 1) Сбор данных от пользователя
#
read -p "Домен (например: supabase.example.com): " DOMAIN
read -p "Email для SSL и уведомлений: " EMAIL
read -p "Логин для Supabase Studio: " DASHBOARD_USERNAME
read -s -p "Пароль для Studio и nginx Basic Auth: " DASHBOARD_PASSWORD
echo ""
SITE_URL="https://${DOMAIN}"

#
# 2) Генерация секретов
#
log "INFO" "🔑 Генерация секретов..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -hex 32)

#
# 3) Установка базовых пакетов
#
log "INFO" "📦 Установка пакетов..."
apt update
apt install -y \
  ca-certificates curl gnupg lsb-release \
  git jq htop net-tools ufw unzip \
  nginx apache2-utils certbot python3-certbot-nginx openssl

#
# 4) Установка Docker Engine и Compose-плагина
#
log "INFO" "🐳 Установка Docker..."
install -m0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
ARCH=$(dpkg --print-architecture)
RELEASE=$(. /etc/os-release && echo "$VERSION_CODENAME")
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu ${RELEASE} stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y docker-ce docker-ce-cli containerd.io \
               docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

#
# 5) Настройка файрвола
#
log "INFO" "🛡️ Настройка UFW..."
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable

#
# 6) Подготовка директорий
#
log "INFO" "📁 Подготовка директорий..."
mkdir -p /opt/supabase /opt/supabase-project

#
# 7) Конфигурируем Nginx + Basic Auth, проксируем через Kong (порт 8000)
#
log "INFO" "💻 Настройка Nginx и Basic Auth..."
htpasswd -bc /etc/nginx/.htpasswd "$DASHBOARD_USERNAME" "$DASHBOARD_PASSWORD"

cat <<'NGINX' >/etc/nginx/sites-available/supabase
server {
  listen 80;
  server_name DOMAIN_PLACEHOLDER;

  location / {
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;

    # проксируем через Kong на порт 8000
    proxy_pass http://localhost:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

    # передаём ANON_KEY для аутентификации в Kong
    proxy_set_header Authorization "Bearer ANON_KEY_PLACEHOLDER";
  }
}
NGINX

# подставляем реальные значения
sed -i "s|DOMAIN_PLACEHOLDER|${DOMAIN}|g" /etc/nginx/sites-available/supabase
sed -i "s|ANON_KEY_PLACEHOLDER|${ANON_KEY}|g" /etc/nginx/sites-available/supabase

ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/supabase
nginx -t && systemctl reload nginx

#
# 8) Получение тестового SSL-сертификата (staging)
#
log "INFO" "🔒 Запрос тестового SSL (staging)..."
certbot --nginx -d "$DOMAIN" -m "$EMAIL" --agree-tos -n --staging

#
# 9) Клонирование Supabase и sparse-checkout docker
#
log "INFO" "⬇️ Клонирование Supabase..."
git clone --depth 1 --filter=blob:none --sparse \
  https://github.com/supabase/supabase.git /opt/supabase
cd /opt/supabase
git sparse-checkout init --cone
git sparse-checkout set docker

#
# 10) Копирование Docker-манифестов
#
log "INFO" "📄 Копирование Docker-манифестов..."
cp -r docker/* /opt/supabase-project/

#
# 11) Генерация .env из шаблона
#
log "INFO" "✍️ Создание .env..."
cd /opt/supabase-project
cp ../supabase/docker/.env.example .env

# заполняем ключевые поля
sed -i "s|^#\?POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${POSTGRES_PASSWORD}|g" .env
sed -i "s|^#\?ANON_KEY=.*|ANON_KEY=${ANON_KEY}|g" .env
sed -i "s|^#\?SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}|g" .env
sed -i "s|^#\?JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|g" .env
sed -i "s|^#\?SITE_URL=.*|SITE_URL=${SITE_URL}|g" .env
sed -i "s|^#\?SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=${SITE_URL}|g" .env
sed -i "s|^#\?DASHBOARD_USERNAME=.*|DASHBOARD_USERNAME=${DASHBOARD_USERNAME}|g" .env
sed -i "s|^#\?DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD}|g" .env
sed -i "s|^#\?SMTP_ADMIN_EMAIL=.*|SMTP_ADMIN_EMAIL=${EMAIL}|g" .env

# оставляем пустые токены Logflare, чтобы Vector не падал
sed -i "s|^#\?LOGFLARE_PUBLIC_ACCESS_TOKEN=.*|LOGFLARE_PUBLIC_ACCESS_TOKEN=\"\"|g" .env
sed -i "s|^#\?LOGFLARE_PRIVATE_ACCESS_TOKEN=.*|LOGFLARE_PRIVATE_ACCESS_TOKEN=\"\"|g" .env

#
# 12) Запуск Supabase
#
log "INFO" "🐳 Запуск контейнеров Supabase..."
docker compose pull
docker compose up -d --remove-orphans

log "INFO" "✅ Установка завершена! Откройте ${SITE_URL}"
