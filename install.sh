#!/usr/bin/env bash
set -euo pipefail

# === Опрос ===
read -p "Введите ваш IP или домен: " IP_DOMAIN
read -p "Введите ваш email для SSL: " EMAIL
read -p "Введите имя пользователя для входа: " DASH_USER
read -p "Введите пароль для входа: " DASH_PASS

# === Система ===
apt update && apt upgrade -y
apt install -y curl git jq apache2-utils nginx certbot python3-certbot-nginx

curl -fsSL https://get.docker.com | sh
LATEST_TAG=$(curl -s https://api.github.com/repos/supabase/cli/releases/latest | jq -r '.tag_name')
DEB_URL=$(curl -s https://api.github.com/repos/supabase/cli/releases/latest | jq -r '.assets[] | select(.browser_download_url | endswith("_linux_amd64.deb")) | .browser_download_url')
curl -L "$DEB_URL" -o supabase-cli.deb
dpkg -i supabase-cli.deb

mkdir -p ~/ws-supabase && cd ~/ws-supabase
supabase init

POSTGRES_PASS=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 20)
ANON_KEY=$(openssl rand -hex 20)
SERVICE_KEY=$(openssl rand -hex 20)

# === Определяем правильную папку ===
if [ -d "supabase" ]; then
  ENV_DIR="supabase"
elif [ -d ".supabase" ]; then
  ENV_DIR=".supabase"
else
  echo "Ошибка: папка Supabase не найдена!"
  exit 1
fi

ENV_EXAMPLE_PATH="$ENV_DIR/env.example"

if [ ! -f "$ENV_EXAMPLE_PATH" ]; then
  echo "Создаю env.example с шаблоном..."
  cat <<EOF > "$ENV_EXAMPLE_PATH"
POSTGRES_PASSWORD=
JWT_SECRET=
ANON_KEY=
SERVICE_ROLE_KEY=
SITE_URL=
SUPABASE_PUBLIC_URL=
DASHBOARD_USERNAME=
DASHBOARD_PASSWORD=
EOF
fi

cp "$ENV_EXAMPLE_PATH" "$ENV_DIR/.env"

cat <<EOF >> "$ENV_DIR/.env"
POSTGRES_PASSWORD=$POSTGRES_PASS
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_KEY
SITE_URL=https://$IP_DOMAIN
SUPABASE_PUBLIC_URL=https://$IP_DOMAIN
DASHBOARD_USERNAME=$DASH_USER
DASHBOARD_PASSWORD=$DASH_PASS
EOF

cd "$ENV_DIR"
supabase start

htpasswd -bc /etc/nginx/.htpasswd $DASH_USER $DASH_PASS

cat <<EOL > /etc/nginx/sites-available/supabase
server {
    listen 80;
    server_name $IP_DOMAIN;

    location / {
        proxy_pass http://localhost:54323;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        auth_basic "Restricted Area";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}
EOL

ln -s /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/
systemctl restart nginx

certbot --nginx -d $IP_DOMAIN --agree-tos -m $EMAIL --redirect --non-interactive

cat <<UPDATE > ~/ws-supabase/update.sh
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR=~/ws-supabase/backups
mkdir -p $BACKUP_DIR
rm -rf $BACKUP_DIR/*
ZIP_NAME="backup-$(date +%F-%H%M).zip"
zip -r $BACKUP_DIR/$ZIP_NAME ~/ws-supabase/$ENV_DIR ~/ws-supabase/$ENV_DIR/.env

apt update && apt upgrade -y
LATEST_TAG=$(curl -s https://api.github.com/repos/supabase/cli/releases/latest | jq -r '.tag_name')
DEB_URL=$(curl -s https://api.github.com/repos/supabase/cli/releases/latest | jq -r '.assets[] | select(.browser_download_url | endswith("_linux_amd64.deb")) | .browser_download_url')
curl -L "$DEB_URL" -o supabase-cli.deb
dpkg -i supabase-cli.deb

cd ~/ws-supabase/$ENV_DIR
docker compose pull
docker compose up -d
docker system prune -af
UPDATE

chmod +x ~/ws-supabase/update.sh
(crontab -l 2>/dev/null; echo "0 3 * * * /bin/bash ~/ws-supabase/update.sh >> ~/ws-supabase/update.log 2>&1") | crontab -

echo "=== УСТАНОВКА ЗАВЕРШЕНА ==="
echo "Docker version: $(docker --version)"
echo "Compose version: $(docker compose version)"
echo "Supabase CLI version: $(supabase --version)"
echo

echo "🌐 Dashboard: https://$IP_DOMAIN"
echo "👤 Username: $DASH_USER"
echo "🔑 Password: $DASH_PASS"
echo

echo "🔐 Postgres password: $POSTGRES_PASS"
echo "🔐 JWT_SECRET: $JWT_SECRET"
echo "🔐 ANON_KEY: $ANON_KEY"
echo "🔐 SERVICE_ROLE_KEY: $SERVICE_KEY"
echo

echo "📦 Бэкап хранится в: ~/ws-supabase/backups"
