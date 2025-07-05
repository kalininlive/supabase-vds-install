#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] $2"
}

if [[ $EUID -ne 0 ]]; then
  log "ERROR" "This script must be run as root"
  exit 1
fi

log "INFO" "🚀 Starting Supabase self-host install..."

#
# 0) Clean previous installs
#
rm -rf /opt/supabase /opt/supabase-project

#
# 1) Gather user input
#
read -p "Enter your domain (e.g. supabase.example.com): " DOMAIN
read -p "Enter email for SSL and notifications: " EMAIL
read -p "Enter Supabase Studio login: " DASHBOARD_USERNAME
read -s -p "Enter Supabase Studio/nginx password: " DASHBOARD_PASSWORD
echo ""
SITE_URL="https://${DOMAIN}"

#
# 2) Generate secrets
#
log "INFO" "🔑 Generating secrets..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)

#
# 3) Install base packages
#
log "INFO" "📦 Installing base packages..."
apt update
apt install -y \
  ca-certificates curl gnupg lsb-release \
  git jq htop net-tools ufw unzip \
  openssl nginx apache2-utils certbot python3-certbot-nginx

#
# 4) Add Docker repo and install Docker Engine + Compose plugin
#
log "INFO" "🐳 Installing Docker Engine & Compose plugin..."
install -m0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

ARCH="$(dpkg --print-architecture)"
RELEASE="$(. /etc/os-release && echo "$VERSION_CODENAME")"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu ${RELEASE} stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io \
               docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

#
# 5) Configure firewall
#
log "INFO" "🛡️ Configuring UFW..."
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable

#
# 6) Prepare directories
#
log "INFO" "📁 Preparing directories..."
mkdir -p /opt/supabase /opt/supabase-project

#
# 7) Configure Nginx + Basic Auth
#
log "INFO" "💻 Configuring Nginx and HTTP auth..."
htpasswd -bc /etc/nginx/.htpasswd "$DASHBOARD_USERNAME" "$DASHBOARD_PASSWORD"
cat <<EOF >/etc/nginx/sites-available/supabase
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        auth_basic "Restricted";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}
EOF
ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/supabase
nginx -t && systemctl reload nginx

#
# 8) Obtain test SSL cert (staging)
#
log "INFO" "🔒 Requesting staging SSL certificate..."
certbot --nginx -d "$DOMAIN" -m "$EMAIL" --agree-tos -n --staging

#
# 9) Clone Supabase repo and sparse-checkout Docker
#
log "INFO" "⬇️ Cloning Supabase repo..."
git clone --depth 1 --filter=blob:none --sparse \
    https://github.com/supabase/supabase.git /opt/supabase
cd /opt/supabase
git sparse-checkout init --cone
git sparse-checkout set docker

#
# 10) Copy Docker manifests
#
log "INFO" "📄 Copying Docker manifests..."
cp -r docker/* /opt/supabase-project/

#
# 11) Generate .env
#
log "INFO" "✍️ Writing .env..."
cat <<EOF >/opt/supabase-project/.env
# Database
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# JWT
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
JWT_SECRET=$JWT_SECRET

# URLs
SITE_URL=$SITE_URL
SUPABASE_PUBLIC_URL=$SITE_URL

# SMTP (optional)
SMTP_HOST=
SMTP_PORT=
SMTP_ADMIN_EMAIL=$EMAIL

# Docker socket
DOCKER_SOCKET_LOCATION=/var/run/docker.sock

# Studio auth
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD

# Logflare (must be quoted, even if empty, to satisfy Vector's TOML parser)
LOGFLARE_PUBLIC_ACCESS_TOKEN=""
LOGFLARE_PRIVATE_ACCESS_TOKEN=""
EOF

#
# 12) Launch Supabase stack
#
log "INFO" "🐳 Launching Supabase stack..."
cd /opt/supabase-project
docker compose pull
docker compose up -d --remove-orphans

log "INFO" "✅ Installation complete! Browse to $SITE_URL"
