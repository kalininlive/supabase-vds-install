#!/usr/bin/env bash
set -euo pipefail

# === 1. Опрос пользователя ===
read -p "Введите ваш IP или домен: " IP_DOMAIN
read -p "Введите ваш email для SSL: " EMAIL
read -p "Введите имя пользователя для входа: " DASH_USER
read -p "Введите пароль для входа: " DASH_PASS

# Зависимости
apt update && apt upgrade -y
apt install -y curl git jq apache2-utils nginx certbot python3-certbot-nginx unzip

# Docker
curl -fsSL https://get.docker.com | sh

# Клонируем self-hosted репозиторий Supabase
cd ~
git clone https://github.com/supabase/supabase.git
cd supabase/docker

# Генерируем .env
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

# Запуск Supabase
docker compose up -d

# NGINX + Basic Auth
htpasswd -bc /etc/nginx/.htpasswd $DASH_USER $DASH_PASS
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
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
        auth_basic "Restricted";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}
EOL
ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

# SSL через Certbot
certbot --nginx -d $IP_DOMAIN --agree-tos -m $EMAIL --redirect --non-interactive

# Автобэкап и автообновление
cat <<'UPDATE' > ~/ws-supabase/backup_update.sh
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR=~/ws-supabase/backups
mkdir -p "$BACKUP_DIR"
rm -rf "$BACKUP_DIR"/*
ZIP_NAME="backup-$(date +%F-%H%M).zip"
zip -r "$BACKUP_DIR/$ZIP_NAME" ~/supabase/docker/.env
cd ~/supabase/docker
docker compose pull
docker compose up -d
docker system prune -af
UPDATE
chmod +x ~/ws-supabase/backup_update.sh
(crontab -l 2>/dev/null; echo "0 3 * * * /bin/bash ~/ws-supabase/backup_update.sh >> ~/ws-supabase/update.log 2>&1") | crontab -

# Финальный вывод
echo "=== УСТАНОВКА SUPABASE ЗАВЕРШЕНА ==="
echo "URL Dashboard: https://$IP_DOMAIN"
echo "Login: $DASH_USER, Password: $DASH_PASS"
echo "Postgres password: $POSTGRES_PASS"
echo "JWT secret: $JWT_SECRET"
echo "Anon key: $ANON_KEY"
echo "Service role key: $SERVICE_KEY"
echo "Backup script: ~/ws-supabase/backup_update.sh"
