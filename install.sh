#!/usr/bin/env bash

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "❌ Запускать нужно с правами root или через sudo"
  exit 1
fi

echo "🔹 Введите доменное имя (например: supabase.example.com):"
read -r DOMAIN

echo "🔹 Введите email для SSL сертификата и уведомлений Certbot:"
read -r EMAIL

echo "🔹 Введите логин для Supabase Studio:"
read -r DASHBOARD_USERNAME

echo "🔹 Введите пароль для Supabase Studio (будет скрыт):"
read -rs DASHBOARD_PASSWORD
echo ""

echo "🔐 Генерируем секретные ключи..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
SUPABASE_DB_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SECRET_KEY_BASE=$(openssl rand -hex 64)
VAULT_ENC_KEY=$(openssl rand -hex 64)
SITE_URL="https://$DOMAIN"

echo "Обновляем систему и устанавливаем зависимости..."
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
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
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

echo "Копируем docker-compose и конфиги..."
cp -r supabase/docker ./docker
cp docker/docker-compose.yml ./

echo "Готовим конфиг для Vector..."
# Убедимся, что есть папка vector и пример config
if [ ! -d vector ]; then
  mkdir -p vector
fi

if [ ! -f vector/vector.yml ]; then
  echo "Загружаем пример vector.yml из репозитория..."
  curl -fsSL https://raw.githubusercontent.com/supabase/supabase/master/docker/vector/vector.yml -o vector/vector.yml
fi

echo "Фиксим монтирование vector.yml в docker-compose.yml..."
# Правильное монтирование файла vector.yml для vector сервиса
sed -i '/vector:/,/volumes:/{
  /volumes:/a\      - ./vector/vector.yml:/etc/vector/vector.yml:ro
}' docker-compose.yml

# Удаляем возможное монтирование директории vector (если есть)
sed -i '/- .\/vector:\/etc\/vector:ro/d' docker-compose.yml

echo "Фиксим путь к docker.sock..."
sed -i 's|:/var/run/docker.sock:ro,z|/var/run/docker.sock:/var/run/docker.sock:ro,z|' docker-compose.yml || true

echo "Создаем файл .env с полным набором переменных..."
cat > .env <<EOF
# Supabase environment variables

# Database
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
SUPABASE_DB_PASSWORD=$SUPABASE_DB_PASSWORD

# JWT and keys
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
SECRET_KEY_BASE=$SECRET_KEY_BASE
VAULT_ENC_KEY=$VAULT_ENC_KEY

# Studio credentials
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD

# URLs and domains
SITE_URL=$SITE_URL
DOMAIN=$DOMAIN

# Docker and pooler settings (по умолчанию)
DOCKER_SOCKET_LOCATION=/var/run/docker.sock
POOLER_MAX_CLIENT_CONN=20
POOLER_DEFAULT_POOL_SIZE=10

# Studio defaults
STUDIO_DEFAULT_ORGANIZATION=default_org
STUDIO_DEFAULT_PROJECT=default_project

# JWT expiry in seconds (1 час)
JWT_EXPIRY=3600

# Email для certbot (для почты в nginx/certbot)
CERTBOT_EMAIL=$EMAIL

# Другие переменные можно добавить при необходимости
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
if ! certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL"; then
  echo "⚠️ Не удалось получить SSL сертификат. Проверьте домен и email."
fi

echo "Запускаем контейнеры Supabase..."
docker compose --env-file .env -f docker-compose.yml up -d

echo "Ждем 10 секунд, чтобы контейнеры полностью поднялись..."
sleep 10

echo "Получаем S3 Access Key и Secret Key из контейнера Storage (MinIO)..."
STORAGE_CONTAINER=$(docker ps --filter "name=storage" --format "{{.Names}}" | head -n1)

if [ -z "$STORAGE_CONTAINER" ]; then
  echo "⚠️ Не удалось найти контейнер Storage (MinIO)."
  S3_ACCESS_KEY="не найден"
  S3_SECRET_KEY="не найден"
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
echo "SSL Email:          $EMAIL"
echo "----------------------------------------"
