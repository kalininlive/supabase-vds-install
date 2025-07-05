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
apt install -y curl git jq apache2-utils nginx certbot python3-certbot-nginx

# === 3. Установка Docker ===
curl -fsSL https://get.docker.com | sh

# === 4. Скачивание и установка Supabase CLI ===
LATEST_TAG=$(curl -s https://api.github.com/repos/supabase/cli/releases/latest | jq -r '.tag_name')
DEB_URL=$(curl -s https://api.github.com/repos/supabase/cli/releases/latest \
  | jq -r '.assets[] | select(.browser_download_url | endswith("_linux_amd64.deb")) | .browser_download_url')
curl -L "$DEB_URL" -o supabase-cli.deb
dpkg -i supabase-cli.deb

# === 5. Установка yq для патчинга ===
wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod +x /usr/local/bin/yq

# === 6. Инициализация Supabase ===
mkdir -p ~/ws-supabase && cd ~/ws-supabase
supabase init

# === 7. Генерация секретов ===
POSTGRES_PASS=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 20)
ANON_KEY=$(openssl rand -hex 20)
SERVICE_KEY=$(openssl rand -hex 20)

# === 8. Определение директории проекта ===
if [ -d "supabase" ]; then
  ENV_DIR="supabase"
elif [ -d ".supabase" ]; then
  ENV_DIR=".supabase"
else
  echo "❌ Папка Supabase не найдена!"
  exit 1
fi

# === 9. Генерация .env ===
ENV_EXAMPLE_PATH="$ENV_DIR/env.example"
if [ ! -f "$ENV_EXAMPLE_PATH" ]; then
  echo "Создаю env.example..."
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

# === 10. Патчинг docker-compose.yml ===
yq eval ".services.gotrue.environment.JWT_SECRET = \"$JWT_SECRET\"" -i "$ENV_DIR/docker-compose.yml"

# === 11. Запуск Supabase ===
cd "$ENV_DIR"
supabase start

# === 12. Настройка Nginx и Basic Auth ===
htpasswd -bc /etc/nginx/.htpasswd $DASH_USER $DASH_PASS
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
cat <<EOL > /etc/nginx/sites-available/supabase
server {
    listen 80;
    server_name $IP_DOMAIN;

    location / {
        proxy_pass http://localhost:54323;
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

# === 13. Установка SSL через Certbot ===
certbot --nginx -d $IP_DOMAIN --agree-tos -m $EMAIL --redirect --non-interactive

# === Финальный вывод ===
echo "\n✅ Установка Supabase завершена!"
echo "  Dashboard: https://$IP_DOMAIN"
echo "  Username: $DASH_USER"
echo "  Password: $DASH_PASS"
echo "  Postgres password: $POSTGRES_PASS"
echo "  JWT_SECRET: $JWT_SECRET"
echo "  ANON_KEY: $ANON_KEY"
echo "  SERVICE_ROLE_KEY: $SERVICE_KEY"
