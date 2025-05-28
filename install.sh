\#!/usr/bin/env bash

set -e

# 🔹 Ввод переменных пользователем

echo "🔹 Введите домен (например: supabase.example.com):"
read DOMAIN

echo "🔹 Введите логин для Supabase Studio:"
echo -n "Логин: "
read DASHBOARD\_USERNAME

echo -n "Пароль: "
read -s DASHBOARD\_PASSWORD
echo

# 🛠 Генерация паролей и ключей

POSTGRES\_PASSWORD=\$(openssl rand -hex 16)
SUPABASE\_DB\_PASSWORD=\$(openssl rand -hex 16)
JWT\_SECRET=\$(openssl rand -hex 32)
ANON\_KEY=\$(openssl rand -hex 32)
SERVICE\_ROLE\_KEY=\$(openssl rand -hex 32)

SITE\_URL="https\://\$DOMAIN"

# 📦 Установка Docker и Docker Compose

apt update && apt upgrade -y
apt install -y curl git
curl -fsSL [https://get.docker.com](https://get.docker.com) -o get-docker.sh && sh get-docker.sh
apt install -y docker-compose-plugin

# 🔧 Установка утилит

apt install -y ca-certificates gnupg2 lsb-release software-properties-common nginx certbot python3-certbot-nginx apache2-utils

# 🛠 Подготовка Supabase

mkdir -p /opt/supabase && cd /opt/supabase
git clone [https://github.com/supabase/supabase.git](https://github.com/supabase/supabase.git) --depth=1
cp -r supabase/docker .

# 🔐 Настраиваем basic auth

htpasswd -cb /etc/nginx/.htpasswd "\$DASHBOARD\_USERNAME" "\$DASHBOARD\_PASSWORD"

# 📝 Сохраняем переменные в .env

cat <<EOF > .env
SUPABASE\_DB\_PASSWORD=\$SUPABASE\_DB\_PASSWORD
POSTGRES\_PASSWORD=\$POSTGRES\_PASSWORD
JWT\_SECRET=\$JWT\_SECRET
ANON\_KEY=\$ANON\_KEY
SERVICE\_ROLE\_KEY=\$SERVICE\_ROLE\_KEY
DASHBOARD\_USERNAME=\$DASHBOARD\_USERNAME
DASHBOARD\_PASSWORD=\$DASHBOARD\_PASSWORD
SITE\_URL=\$SITE\_URL
DOMAIN=\$DOMAIN
EOF

cp docker/docker-compose.yml .

# 🌐 Настройка nginx

cat <<EOF > /etc/nginx/sites-available/supabase
server {
listen 80;
server\_name \$DOMAIN;

```
location / {
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;
    proxy_pass http://localhost:54323;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
}
```

}
EOF

ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/supabase
nginx -t && systemctl reload nginx

# 🔒 SSL-сертификат

certbot --nginx -d "\$DOMAIN"

# 🚀 Запуск Supabase

cd /opt/supabase
docker compose -f docker/docker-compose.yml up -d

# 📋 Финальный вывод

clear
echo "\n✅ Установка завершена. Ниже важные данные:"
echo "----------------------------------------"
echo "Studio URL:         \$SITE\_URL"
echo "API URL:            \$SITE\_URL"
echo "DB:                 postgres\://postgres:\$POSTGRES\_PASSWORD\@localhost:5432/postgres"
echo "JWT\_SECRET:         \$JWT\_SECRET"
echo "anon key:           \$ANON\_KEY"
echo "service\_role key:   \$SERVICE\_ROLE\_KEY"
echo "Studio login:       \$DASHBOARD\_USERNAME"
echo "Studio password:    \$DASHBOARD\_PASSWORD"
echo "Домен:              \$DOMAIN"
echo "----------------------------------------"
echo "\n💡 Эти данные понадобятся тебе для настройки n8n и других сервисов."
