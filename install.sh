#!/usr/bin/env bash
set -euo pipefail

# === 1. Опрос пользователя ===
read -p "Введите ваш IP или домен: " IP_DOMAIN
read -p "Введите ваш email для SSL: " EMAIL
read -p "Введите имя пользователя для входа: " DASH_USER
read -p "Введите пароль для входа: " DASH_PASS

if [ -z "$IP_DOMAIN" ]; then echo "❌ IP или домен пустой!"; exit 1; fi

# === 2. Обновление системы и установка зависимостей ===
apt update && apt upgrade -y
apt install -y curl git jq apache2-utils nginx certbot python3-certbot-nginx unzip 

# === 3. Установка Docker ===
curl -fsSL https://get.docker.com | sh

# === 4. Клонирование репозитория Supabase self-hosted ===
cd ~
git clone https://github.com/supabase/supabase.git supabase-selfhost
cd supabase-selfhost/docker

# === 5. Генерация .env ===
cp .env.example .env
POSTGRES_PASS=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 20)
ANON_KEY=$(openssl rand -hex 20)
SERVICE_KEY=$(openssl rand -hex 20)
cat <<EOF >> .env
POSTGRES_PASSWORD=$POSTGRES_PASS
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_KEY
SITE_URL=https://$IP_DOMAIN
SUPABASE_PUBLIC_URL=https://$IP_DOMAIN
DASHBOARD_USERNAME=$DASH_USER
DASHBOARD_PASSWORD=$DASH_PASS
EOF

# === 6. Запуск Docker Compose ===
docker compose up -d

# === 7. Настройка Nginx и Basic Auth ===
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
htpasswd -bc /etc/nginx/.htpasswd $DASH_USER $DASH_PASS
cat <<EOL > /etc/nginx/sites-available/supabase
server {
    listen 80;
    server_name $IP_DOMAIN;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        auth_basic "Restricted Area";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}
EOL
ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/supabase
nginx -t && systemctl restart nginx

# === 8. Выпуск SSL сертификата ===
certbot --nginx -d $IP_DOMAIN --agree-tos -m $EMAIL --redirect --non-interactive

# === 9. Настройка UFW (фаервол) ===
# Запрет всех входящих, разрешить исходящие
ufw default deny incoming
ufw default allow outgoing
# Разрешить SSH, HTTP, HTTPS
ufw allow ssh
ufw allow http
ufw allow https
# Закрыть порты Supabase (54321–54324)
ufw deny proto tcp from any to any port 54321:54324
# Включить UFW без интерактивного подтверждения
ufw --force enable

# === 10. Финальный вывод ===
echo "
✅ Установка Supabase self-hosted завершена!"
echo "  Dashboard: https://$IP_DOMAIN"
echo "  Username: $DASH_USER"
echo "  Password: $DASH_PASS"
echo "  Postgres password: $POSTGRES_PASS"
echo "  JWT_SECRET: $JWT_SECRET"
echo "  ANON_KEY: $ANON_KEY"
echo "  SERVICE_ROLE_KEY: $SERVICE_KEY"
