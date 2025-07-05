#!/usr/bin/env bash
set -euo pipefail

# Функция логирования
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"
}

if [[ $EUID -ne 0 ]]; then
  log "ERROR" "Скрипт нужно запускать от root или через sudo"
  exit 1
fi

log "INFO" "🚀 Старт установки Supabase..."

#
# 0) Чистим прежние установки (если есть)
#
rm -rf /opt/supabase /opt/supabase-project

#
# 1) Сбор данных от пользователя
#
read -p "Введите домен (supabase.example.com): " DOMAIN
read -p "Введите email для SSL и уведомлений: " EMAIL
read -p "Введите логин для Supabase Studio: " DASHBOARD_USERNAME
read -s -p "Введите пароль для Studio и nginx Basic Auth: " DASHBOARD_PASSWORD
echo ""

SITE_URL="https://$DOMAIN"

#
# 2) Генерация ключей
#
log "INFO" "🔑 Генерация паролей и ключей..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)

#
# 3) Установка базовых пакетов и Certbot
#
log "INFO" "📦 Установка пакетов..."
apt update
apt install -y \
  ca-certificates curl gnupg lsb-release \
  git jq htop net-tools ufw unzip \
  nginx apache2-utils certbot python3-certbot-nginx

#
# 4) Установка Docker Engine и Compose-плагина
#
log "INFO" "🐳 Установка Docker..."
install -m0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
ARCH="$(dpkg --print-architecture)"
RELEASE="$(. /etc/os-release && echo "$VERSION_CODENAME")"
echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $RELEASE stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y docker-ce docker-ce-cli containerd.io \
               docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

#
# 5) Настройка UFW
#
log "INFO" "🛡️ Настройка файрвола..."
ufw allow OpenSSH; ufw allow 80; ufw allow 443
ufw --force enable

#
# 6) Подготовка директорий
#
log "INFO" "📁 Готовим папки..."
mkdir -p /opt/supabase /opt/supabase-project

#
# 7) Настройка Nginx + Basic Auth
#
log "INFO" "💻 Конфигурируем Nginx..."
htpasswd -bc /etc/nginx/.htpasswd "$DASHBOARD_USERNAME" "$DASHBOARD_PASSWORD"
cat <<'NGINX' >/etc/nginx/sites-available/supabase
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        auth_basic "Restricted";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}
NGINX
ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/supabase
nginx -t && systemctl reload nginx

#
# 8) Запрос тестового SSL (staging)
#
log "INFO" "🔒 Запрашиваем тестовый сертификат (staging)..."
certbot --nginx -d "$DOMAIN" -m "$EMAIL" --agree-tos -n --staging

#
# 9) Клонирование Supabase и sparse-checkout
#
log "INFO" "⬇️ Клонируем Supabase..."
git clone --depth=1 --filter=blob:none --sparse \
    https://github.com/supabase/supabase.git /opt/supabase
cd /opt/supabase
git sparse-checkout init --cone
git sparse-checkout set docker

#
# 10) Копирование Docker-файлов
#
log "INFO" "📄 Копируем Docker-манифесты..."
cp -r docker/* /opt/supabase-project/

#
# 11) Генерация .env
#
log "INFO" "✍️ Создаем .env..."
cat <<EOF >/opt/supabase-project/.env
# Database
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# JWT
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
JWT_SECRET=$JWT_SECRET

# URLs
SITE_URL=$SITE_URL
SUPABASE_PUBLIC_URL=$SITE_URL

# SMTP (если надо, заполните)
SMTP_HOST=
SMTP_PORT=
SMTP_ADMIN_EMAIL=$EMAIL

# Docker socket
DOCKER_SOCKET_LOCATION=/var/run/docker.sock

# Studio auth
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD

# Logflare (оставьте пустыми или вставьте свои токены)
LOGFLARE_PUBLIC_ACCESS_TOKEN=
LOGFLARE_PRIVATE_ACCESS_TOKEN=
EOF

#
# 12) Запуск контейнеров
#
log "INFO" "🐳 Запускаем Supabase..."
cd /opt/supabase-project
docker compose pull
docker compose up -d --remove-orphans

log "INFO" "✅ Установка завершена! Проверьте https://$DOMAIN"
