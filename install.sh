#!/usr/bin/env bash

set -euo pipefail

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Запускать нужно с правами root или через sudo"
  exit 1
fi

echo "🔹 Введите доменное имя для Supabase (например: supabase.example.com):"
read -r DOMAIN

echo "🔹 Введите логин для Supabase Studio:"
read -r DASHBOARD_USERNAME

echo "🔹 Введите пароль для Supabase Studio (будет скрыт):"
read -rs DASHBOARD_PASSWORD
echo ""

echo "🔐 Генерация секретных ключей..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
SUPABASE_DB_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SITE_URL="https://$DOMAIN"

echo "Обновляем пакеты и устанавливаем зависимости..."
apt update
apt install -y curl git ca-certificates gnupg lsb-release nginx certbot python3-certbot-nginx apache2-utils

echo "Устанавливаем Docker и Docker Compose..."
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm get-docker.sh
fi

if ! dpkg -s docker-compose-plugin >/dev/null 2>&1; then
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt update
  apt install -y docker-compose-plugin
fi

systemctl enable --now docker

echo "Клонируем репозиторий Supabase..."
mkdir -p /opt/supabase
cd /opt/supabase

if [ ! -d supabase ]; then
  git clone https://github.com/supabase/supabase.git --depth=1
else
  echo "Репозиторий supabase уже существует, обновляем..."
  cd supabase && git pull
  cd ..
fi

cp -r supabase/docker ./docker
cp docker/docker-compose.yml ./

echo "Фиксим путь к docker.sock в docker-compose.yml..."
sed -i 's|:/var/run/docker.sock:ro,z|/var/run/docker.sock:/var/run/docker.sock:ro,z|' docker-compose.yml || true

echo "Создаем .env с параметрами..."
cat > .env <<EOF
SUPABASE_DB_PASSWORD=$SUPABASE_DB_PASSWORD
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD
SITE_URL=$SITE_URL
DOMAIN=$DOMAIN
POSTGRES_DB=postgres
POSTGRES_PORT=5432
POSTGRES_HOST=db
EOF

echo "Настраиваем Nginx с basic auth..."
htpasswd -cb /etc/nginx/.htpasswd "$DASHBOARD_USERNAME" "$DASHBOARD_PASSWORD"

cat > /etc/nginx/sites-available/supabase <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        auth_basic "Restricted";
        auth_basic_user_file /etc/nginx/.htpasswd;
        proxy_pass http://localhost:54323;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/supabase

echo "Проверяем конфигурацию nginx..."
nginx -t

echo "Перезапускаем nginx..."
systemctl reload nginx

echo "Получаем SSL сертификат Let's Encrypt..."
if ! certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN"; then
  echo "⚠️ Не удалось получить SSL сертификат. Проверьте домен и настройки DNS."
fi

echo "Запускаем контейнеры Supabase..."
docker compose --env-file .env -f docker-compose.yml up -d

echo "Ждем 10 секунд, чтобы контейнеры поднялись..."
sleep 10

echo "Получаем S3 Access Key и Secret Key из контейнера MinIO..."
STORAGE_CONTAINER=$(docker ps --filter "name=storage" --format "{{.Names}}" | head -n1)

if [ -z "$STORAGE_CONTAINER" ]; then
  echo "⚠️ Не удалось найти контейнер Storage (MinIO)."
else
  S3_ACCESS_KEY=$(docker exec "$STORAGE_CONTAINER" printenv MINIO_ACCESS_KEY || echo "не найден")
  S3_SECRET_KEY=$(docker exec "$STORAGE_CONTAINER" printenv MINIO_SECRET_KEY || echo "не найден")
fi

clear
echo -e "\n✅ Установка Supabase завершена!\n"
echo "----------------------------------------"
echo "Studio URL:         $SITE_URL"
echo "API URL:            $SITE_URL"
echo "DB URL:             postgres://postgres:$POSTGRES_PASSWORD@localhost:5432/postgres"
echo "JWT_SECRET:         $JWT_SECRET"
echo "anon key:           $ANON_KEY"
echo "service_role key:   $SERVICE_ROLE_KEY"
echo "Studio login:       $DASHBOARD_USERNAME"
echo "Studio password:    $DASHBOARD_PASSWORD"
echo "Домен:              $DOMAIN"
echo "S3 Access Key:      $S3_ACCESS_KEY"
echo "S3 Secret Key:      $S3_SECRET_KEY"
echo "S3 Region:          local"
echo "----------------------------------------"
