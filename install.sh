#!/bin/bash
# Скрипт для полностью автоматической установки Supabase на Ubuntu 22.04
# Официальная документация: https://supabase.com/docs/guides/self-hosting/docker
# Использование: ./install_supabase.sh <домен> <email>
# Если домен и email не переданы как параметры, используйте переменные DOMAIN и EMAIL ниже.

# Выходим при любой ошибке
set -euo pipefail

# Функция логирования с временной меткой
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Проверяем, что скрипт запускается от root (или через sudo)
if [[ "$EUID" -ne 0 ]]; then
    echo "Этот скрипт нужно запускать от имени root." >&2
    exit 1
fi

# Читаем домен и email из аргументов или используем заданные по умолчанию
DOMAIN="${1:-supabase.example.com}"      # Замените на ваш домен
EMAIL="${2:-admin@example.com}"          # Замените на ваш email для уведомлений Let's Encrypt

# Предотвращаем запуск со значениями по умолчанию (example.com), чтобы не получить ошибки
if [[ "$DOMAIN" == *"example.com" ]]; then
    log "ERROR: переменная DOMAIN не настроена. Пожалуйста, укажите свой домен."
    exit 1
fi

log "Начало установки Supabase на домен $DOMAIN"

# Обновляем пакеты и устанавливаем необходимые зависимости
log "Обновление системы и установка зависимостей (Docker, Docker Compose, Nginx, Certbot, Git, UFW)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
# Устанавливаем Docker (через официальный репозиторий) и другие инструменты
apt-get install -y ca-certificates curl gnupg lsb-release openssl
# Добавляем ключ и репозиторий Docker
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
# Устанавливаем прочие пакеты
apt-get install -y nginx git snapd ufw psmisc

# Включаем автозапуск Docker при загрузке системы
log "Включение службы Docker при старте системы..."
systemctl enable docker

# Настраиваем firewall (UFW): открываем только 22/SSH, 80/HTTP, 443/HTTPS, закрываем остальные
log "Настройка брандмауэра UFW: разрешены порты 22, 80, 443; остальные закрыты."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw --force enable

# Настраиваем директорию для веб-ресурса сертификатов
mkdir -p /var/www/certbot
chown www-data:www-data /var/www/certbot

# Конфигурация Nginx для первоначального получения сертификата (HTTP challenge)
log "Настройка Nginx для выдачи сертификата Let's Encrypt..."
# Отключаем конфигурацию по умолчанию, если она есть
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-available/default
# Создаем временную конфигурацию Nginx (только для HTTP, для проверки домена)
cat > /etc/nginx/sites-available/supabase.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    root /var/www/certbot;
    location /.well-known/acme-challenge/ {
        allow all;
    }
}
EOF
ln -s /etc/nginx/sites-available/supabase.conf /etc/nginx/sites-enabled/supabase.conf
# Запускаем Nginx с новой конфигурацией
systemctl restart nginx

# Получаем сертификат Let's Encrypt (без участия человека, с помощью веб-сервера)
log "Получение SSL-сертификата для $DOMAIN через Certbot..."
snap install core && snap refresh core
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true
certbot certonly --webroot -w /var/www/certbot -d "$DOMAIN" --deploy-hook "systemctl reload nginx" --email "$EMAIL" --no-eff-email --agree-tos --non-interactive

# Сохраняем пути к выданному сертификату и ключу
CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

# Генерируем случайные секреты для Supabase (JWT, пароли и ключи)
log "Генерация секретных ключей и паролей для Supabase..."
# Функция для генерации случайной строки заданной длины (из букв и цифр)
generate_secret() {
    # Читаем много байт из /dev/urandom, фильтруем только алфавитно-цифровые символы
    head -c 256 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c "$1"
}
POSTGRES_PASSWORD=$(generate_secret 16)      # пароль Postgres (16 символов)
JWT_SECRET=$(generate_secret 32)             # секрет JWT (не менее 32 символов)
DASHBOARD_USERNAME="supabase"                # логин для Basic Auth (и панели админки Supabase)
DASHBOARD_PASSWORD=$(generate_secret 16)     # пароль для Basic Auth (16 символов)
# Создаем уникальные JWT-токены для анонимного доступа и сервисного доступа (anon и service_role)
NOW=$(date +%s)
EXP=$((NOW + 60*60*24*365*5))  # срок действия 5 лет от текущей даты
# Функция для кодирования JSON строки в Base64 URL-safe без '='
b64url() {
    openssl base64 -A | tr -d '=' | tr '/+' '_-'
}
# Заголовок JWT
HEADER_B64=$(printf '{"alg":"HS256","typ":"JWT"}' | b64url)
# Полезная нагрузка (payload) для анонимного ключа
PAYLOAD_ANON=$(printf '{"role":"anon","iss":"supabase","iat":%d,"exp":%d}' "$NOW" "$EXP")
PAYLOAD_ANON_B64=$(printf '%s' "$PAYLOAD_ANON" | b64url)
# Подпись JWT HMAC-SHA256 для anon
SIG_ANON=$(printf '%s' "$HEADER_B64.$PAYLOAD_ANON_B64" | openssl dgst -sha256 -hmac "$JWT_SECRET" -binary | base64 -w0 | tr -d '=' | tr '/+' '_-')
ANON_KEY="$HEADER_B64.$PAYLOAD_ANON_B64.$SIG_ANON"
# Полезная нагрузка для сервисного ключа (service_role)
PAYLOAD_SERVICE=$(printf '{"role":"service_role","iss":"supabase","iat":%d,"exp":%d}' "$NOW" "$EXP")
PAYLOAD_SERVICE_B64=$(printf '%s' "$PAYLOAD_SERVICE" | b64url)
SIG_SERVICE=$(printf '%s' "$HEADER_B64.$PAYLOAD_SERVICE_B64" | openssl dgst -sha256 -hmac "$JWT_SECRET" -binary | base64 -w0 | tr -d '=' | tr '/+' '_-')
SERVICE_ROLE_KEY="$HEADER_B64.$PAYLOAD_SERVICE_B64.$SIG_SERVICE"
# Дополнительные секреты
SECRET_KEY_BASE=$(openssl rand -base64 48)   # секретный ключ приложения (для internal, например шифрование)
VAULT_ENC_KEY=$(openssl rand -hex 16)        # ключ шифрования для Vault (32 hex-символа)

# Клонируем официальный репозиторий Supabase (содержит docker-compose.yml и .env.example)
log "Загрузка Docker-конфигурации Supabase (клонирование репозитория supabase)..."
git clone --depth 1 https://github.com/supabase/supabase.git /opt/supabase
cd /opt/supabase/docker

# Копируем шаблон переменных окружения и настраиваем его
cp .env.example .env
log "Настройка файла окружения .env для Supabase..."
# Обновляем необходимые переменные окружения в .env на сгенерированные значения
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" .env
sed -i "s/^JWT_SECRET=.*/JWT_SECRET=$JWT_SECRET/" .env
sed -i "s/^ANON_KEY=.*/ANON_KEY=$ANON_KEY/" .env
sed -i "s/^SERVICE_ROLE_KEY=.*/SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY/" .env
sed -i "s/^DASHBOARD_USERNAME=.*/DASHBOARD_USERNAME=$DASHBOARD_USERNAME/" .env
sed -i "s/^DASHBOARD_PASSWORD=.*/DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD/" .env
sed -i "s|^SITE_URL=.*|SITE_URL=https://$DOMAIN|" .env
sed -i "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=$SECRET_KEY_BASE/" .env
sed -i "s/^VAULT_ENC_KEY=.*/VAULT_ENC_KEY=$VAULT_ENC_KEY/" .env

# Добавляем политику рестарта для всех сервисов Docker Compose (restart: always)
log "Конфигурация Docker Compose: включение автозапуска контейнеров (restart: always)..."
sed -i -E '/^  [A-Za-z0-9_-]+:$/a \    restart: always' docker-compose.yml

# Запускаем контейнеры Supabase через Docker Compose
log "Запуск сервисов Supabase в Docker..."
docker compose pull   # загружаем последние образы
docker compose up -d

# Настраиваем Nginx с SSL и Basic Auth для проксирования Supabase
log "Настройка Nginx (HTTPS + Basic Auth) для домена $DOMAIN..."
# Создаем файл паролей для Basic Auth
HTPASSWD_ENTRY="${DASHBOARD_USERNAME}:$(openssl passwd -apr1 "$DASHBOARD_PASSWORD")"
echo "$HTPASSWD_ENTRY" > /etc/nginx/.htpasswd

# Обновляем конфигурацию Nginx для HTTPS, прокси и защиты паролем
cat > /etc/nginx/sites-available/supabase.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    root /var/www/certbot;
    location /.well-known/acme-challenge/ {
        allow all;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}
server {
    listen 443 ssl;
    server_name $DOMAIN;
    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;
    # Включаем базовую авторизацию (Basic Auth) для всего домена
    auth_basic "Restricted Access";
    auth_basic_user_file /etc/nginx/.htpasswd;
    location / {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        # Передаем заголовки для поддержки WebSocket (Realtime)
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

# Применяем новую конфигурацию Nginx
nginx -t && systemctl reload nginx

log "Установка Supabase завершена. Данные для доступа:"
echo "======================================================================"
echo "Supabase успешно установлен и работает по адресу: https://$DOMAIN"
echo "Доступ защищен Basic Auth."
echo "Логин: $DASHBOARD_USERNAME"
echo "Пароль: $DASHBOARD_PASSWORD"
echo ""
echo "Параметры базы данных (PostgreSQL):"
echo "  Хост: localhost"
echo "  Порт: 5432"
echo "  Пользователь: postgres"
echo "  Пароль: $POSTGRES_PASSWORD"
echo ""
echo "JWT Secret (секрет для JWT): $JWT_SECRET"
echo "Anon Key (ключ анонимного доступа): $ANON_KEY"
echo "Service Role Key (ключ сервисного доступа): $SERVICE_ROLE_KEY"
echo "======================================================================"
