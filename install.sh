#!/usr/bin/env bash
set -euo pipefail

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"; }
if [[ $EUID -ne 0 ]]; then log "ERROR" "Запустите от root"; exit 1; fi

log "INFO" "🚀 Старт установки Supabase..."

# 0) Очистка
rm -rf /opt/supabase /opt/supabase-project

# 1) Ввод
read -p "Домен (например: supabase.example.com): " DOMAIN
read -p "Email для SSL и уведомлений: " EMAIL
read -p "Логин для Studio: " DASHBOARD_USERNAME
read -s -p "Пароль для Studio/BasicAuth: " DASHBOARD_PASSWORD
echo ""
SITE_URL="https://${DOMAIN}"

# 2) Ключи
log "INFO" "🔑 Генерируем ключи..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -hex 32)

# 3) Пакеты
log "INFO" "📦 Устанавливаем пакеты..."
apt update
apt install -y ca-certificates curl gnupg lsb-release \
  git jq htop net-tools ufw unzip \
  nginx apache2-utils certbot python3-certbot-nginx openssl

# 4) Docker
log "INFO" "🐳 Устанавливаем Docker Engine и Compose..."
install -m0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
ARCH=$(dpkg --print-architecture)
RELEASE=$(. /etc/os-release && echo "$VERSION_CODENAME")
echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $RELEASE stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y docker-ce docker-ce-cli containerd.io \
               docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# 5) UFW
log "INFO" "🛡 Настраиваем UFW..."
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable

# 6) Директории
log "INFO" "📁 Готовим каталоги..."
mkdir -p /opt/supabase /opt/supabase-project

# 7) Nginx + Basic Auth прокси на Studio:3000
log "INFO" "💻 Конфигурируем Nginx и Basic Auth..."
htpasswd -bc /etc/nginx/.htpasswd "$DASHBOARD_USERNAME" "$DASHBOARD_PASSWORD"
cat <<'NGINX' >/etc/nginx/sites-available/supabase
server {
  listen 80;
  server_name DOMAIN_PLACEHOLDER;

  location / {
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;

    proxy_pass http://localhost:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
}
NGINX
sed -i "s|DOMAIN_PLACEHOLDER|${DOMAIN}|g" /etc/nginx/sites-available/supabase
ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/supabase
nginx -t && systemctl reload nginx

# 8) SSL (staging)
log "INFO" "🔒 Запрашиваем тестовый сертификат..."
certbot --nginx -d "$DOMAIN" -m "$EMAIL" --agree-tos -n --staging

# 9) Клонирование Supabase
log "INFO" "⬇️ Клонирование Supabase repo..."
git clone --depth 1 --filter=blob:none --sparse \
  https://github.com/supabase/supabase.git /opt/supabase
cd /opt/supabase
git sparse-checkout init --cone
git sparse-checkout set docker

# 10) Копируем Docker-манифесты и правим vector
log "INFO" "📄 Копируем Docker-манифесты..."
cp -r docker/* /opt/supabase-project/

log "INFO" "🔧 Отключаем logflare-sink в Vector..."
if [[ -f /opt/supabase-project/vector/vector.yml ]]; then
  sed -i '/^\[sinks\.logflare_auth\]/,/^\[/{ s/^/#/ }' /opt/supabase-project/vector/vector.yml
fi

# 10.1) Маппим порт Studio:3000
cat <<EOF >/opt/supabase-project/docker-compose.override.yml
version: "3.9"
services:
  studio:
    ports:
      - "3000:3000"
EOF

# 11) Генерируем .env
log "INFO" "✍️ Создаём .env из шаблона..."
cd /opt/supabase-project
cp ../supabase/docker/.env.example .env
sed -i "s|^#\?POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${POSTGRES_PASSWORD}|g" .env
sed -i "s|^#\?ANON_KEY=.*|ANON_KEY=${ANON_KEY}|g" .env
sed -i "s|^#\?SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}|g" .env
sed -i "s|^#\?JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|g" .env
sed -i "s|^#\?SITE_URL=.*|SITE_URL=${SITE_URL}|g" .env
sed -i "s|^#\?SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=${SITE_URL}|g" .env
sed -i "s|^#\?DASHBOARD_USERNAME=.*|DASHBOARD_USERNAME=${DASHBOARD_USERNAME}|g" .env
sed -i "s|^#\?DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD}|g" .env
sed -i "s|^#\?SMTP_ADMIN_EMAIL=.*|SMTP_ADMIN_EMAIL=${EMAIL}|g" .env

# 12) Запуск стека
log "INFO" "🐳 Запуск контейнеров Supabase..."
docker compose pull
docker compose up -d --remove-orphans

log "INFO" "✅ Готово! Откройте ${SITE_URL}"
