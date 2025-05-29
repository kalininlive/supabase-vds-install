#!/usr/bin/env bash

set -euo pipefail

LOG_FILE="/var/log/supabase_install.log"
MAX_LOG_SIZE=$((5 * 1024 * 1024))

rotate_logs() {
  if [ -f "$LOG_FILE" ]; then
    local size
    size=$(stat -c%s "$LOG_FILE")
    if [ "$size" -ge "$MAX_LOG_SIZE" ]; then
      mv "$LOG_FILE" "$LOG_FILE.old"
      touch "$LOG_FILE"
      echo "[INFO] Log rotated: $LOG_FILE.old" >> "$LOG_FILE"
    fi
  else
    touch "$LOG_FILE"
  fi
}

log() {
  local level=$1
  local message=$2
  local color_reset="\e[0m"
  local color=""
  case "$level" in
    INFO) color="\e[34m";;
    WARN) color="\e[33m";;
    ERROR) color="\e[31m";;
    SUCCESS) color="\e[32m";;
    *) color="";;
  esac
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo -e "${color}[$timestamp] [$level] $message${color_reset}"
  echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

disable_ipv6() {
  log INFO "Отключаем IPv6 на время установки..."
  sysctl -w net.ipv6.conf.all.disable_ipv6=1
  sysctl -w net.ipv6.conf.default.disable_ipv6=1
  sysctl -w net.ipv6.conf.lo.disable_ipv6=1
}

enable_ipv6() {
  log INFO "Включаем IPv6 обратно после установки..."
  sysctl -w net.ipv6.conf.all.disable_ipv6=0
  sysctl -w net.ipv6.conf.default.disable_ipv6=0
  sysctl -w net.ipv6.conf.lo.disable_ipv6=0
}

rotate_logs

if [ "$EUID" -ne 0 ]; then
  log ERROR "Запустите скрипт с правами root или через sudo"
  exit 1
fi

disable_ipv6

log INFO "Начинаем установку Supabase..."

read -rp "Введите домен (например: supabase.example.com): " DOMAIN
read -rp "Введите email для SSL сертификата и уведомлений: " EMAIL
read -rp "Введите логин для Supabase Studio: " DASHBOARD_USERNAME
read -rsp "Введите пароль для Supabase Studio и nginx Basic Auth (скрыто): " DASHBOARD_PASSWORD
echo ""

log INFO "Генерируем секретные ключи..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
SUPABASE_DB_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SECRET_KEY_BASE=$(openssl rand -hex 64)
VAULT_ENC_KEY=$(openssl rand -hex 64)

SITE_URL="https://$DOMAIN"

log INFO "Принудительно включаем IPv4 для apt..."
echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4

log INFO "Обновляем систему и устанавливаем зависимости..."
DEBIAN_FRONTEND=noninteractive apt update -y
DEBIAN_FRONTEND=noninteractive apt install -y curl git ca-certificates gnupg lsb-release docker.io docker-compose-plugin nginx certbot python3-certbot-nginx apache2-utils

log INFO "Включаем и запускаем Docker..."
systemctl enable docker --now

log INFO "Клонируем репозиторий Supabase (или обновляем)..."
mkdir -p /opt/supabase
cd /opt/supabase
if [ -d supabase ]; then
  cd supabase
  git fetch --all
  git reset --hard origin/main
  cd ..
  log INFO "Обновили репозиторий Supabase"
else
  git clone https://github.com/supabase/supabase.git --depth=1
  log INFO "Клонировали репозиторий Supabase"
fi

log INFO "Копируем Docker конфигурации..."
cp -r supabase/docker ./docker
cp docker/docker-compose.yml ./

log INFO "Создаём .env с ключами и настройками..."
cat > .env <<EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
SUPABASE_DB_PASSWORD=$SUPABASE_DB_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
SECRET_KEY_BASE=$SECRET_KEY_BASE
VAULT_ENC_KEY=$VAULT_ENC_KEY
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD
SITE_URL=$SITE_URL
DOMAIN=$DOMAIN
POSTGRES_DB=postgres
POSTGRES_PORT=5432
POSTGRES_HOST=db
EOF

log INFO "Настраиваем nginx и Basic Auth..."
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
nginx -t && systemctl reload nginx

log INFO "Получаем SSL сертификат через certbot..."
if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL"; then
  log SUCCESS "SSL сертификат успешно получен"
else
  log WARN "Не удалось получить SSL сертификат (проверьте домен и email)"
fi

log INFO "Запускаем контейнеры Supabase..."
docker compose --env-file .env -f docker-compose.yml up -d

log INFO "Проверяем статус контейнеров..."
for container in $(docker compose ps -q); do
  name=$(docker inspect --format='{{.Name}}' "$container" | cut -c2-)
  health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no healthcheck")
  if [ "$health" != "no healthcheck" ]; then
    if [ "$health" != "healthy" ]; then
      log WARN "Контейнер $name не здоров: $health"
    else
      log INFO "Контейнер $name здоров"
    fi
  else
    log INFO "Контейнер $name без healthcheck, пропускаем проверку"
  fi
done

STORAGE_CONTAINER=$(docker ps --filter "name=storage" --format "{{.Names}}" | head -n1)
if [ -z "$STORAGE_CONTAINER" ]; then
  S3_ACCESS_KEY="не найден"
  S3_SECRET_KEY="не найден"
else
  S3_ACCESS_KEY=$(docker exec "$STORAGE_CONTAINER" printenv MINIO_ACCESS_KEY || echo "не найден")
  S3_SECRET_KEY=$(docker exec "$STORAGE_CONTAINER" printenv MINIO_SECRET_KEY || echo "не найден")
fi

enable_ipv6

cat <<EOF

🚀 Установка Supabase завершена!

Доступы и важные данные:

Studio URL:         $SITE_URL
API URL:            $SITE_URL
DB URL:             postgres://postgres:$POSTGRES_PASSWORD@localhost:5432/postgres

JWT_SECRET:         $JWT_SECRET
anon key:           $ANON_KEY
service_role key:   $SERVICE_ROLE_KEY

Studio login:       $DASHBOARD_USERNAME
Studio/nginx pass:  $DASHBOARD_PASSWORD

Домен:              $DOMAIN

S3 Access Key:      $S3_ACCESS_KEY
S3 Secret Key:      $S3_SECRET_KEY

EOF
