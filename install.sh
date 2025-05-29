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

send_email_report() {
  local subject="$1"
  local body="$2"
  local to_email="$3"

  if command -v mail >/dev/null 2>&1; then
    echo -e "$body" | mail -s "$subject" "$to_email"
    log INFO "Email sent to $to_email"
  else
    log WARN "mail command not found, cannot send email"
  fi
}

check_container_health() {
  local container=$1
  local retries=20
  local wait_sec=6
  local count=0

  log INFO "Checking container health: $container"

  while [ $count -lt $retries ]; do
    local status
    status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unhealthy")
    if [ "$status" == "healthy" ]; then
      log SUCCESS "Container $container is healthy"
      return 0
    fi
    if [ "$status" == "unhealthy" ]; then
      log WARN "Container $container unhealthy, retry $count/$retries"
    fi
    sleep "$wait_sec"
    count=$((count + 1))
  done

  log ERROR "Container $container not healthy after $((retries * wait_sec)) seconds"
  return 1
}

rotate_logs

if [ "$EUID" -ne 0 ]; then
  log ERROR "Run script as root or with sudo"
  exit 1
fi

log INFO "Starting Supabase installation..."

read -rp "Enter domain (e.g. supabase.example.com): " DOMAIN
read -rp "Enter email for SSL cert and notifications: " EMAIL
read -rp "Enter Supabase Studio username: " DASHBOARD_USERNAME
read -rsp "Enter password for Supabase Studio and nginx Basic Auth (hidden): " DASHBOARD_PASSWORD
echo ""

log INFO "Generating secret keys..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
SUPABASE_DB_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
SECRET_KEY_BASE=$(openssl rand -hex 64)
VAULT_ENC_KEY=$(openssl rand -hex 64)

SMTP_USER="supabase_smtp_user"
SMTP_PASS=$(openssl rand -base64 20)

SITE_URL="https://$DOMAIN"

log INFO "Installing dependencies..."
apt update -y >> "$LOG_FILE" 2>&1
apt install -y curl git ca-certificates gnupg lsb-release nginx certbot python3-certbot-nginx apache2-utils mailutils postfix sasl2-bin libsasl2-modules >> "$LOG_FILE" 2>&1
log SUCCESS "Dependencies installed"

log INFO "Configuring Postfix for SMTP auth with generated user..."

systemctl enable saslauthd
systemctl start saslauthd

cat > /etc/postfix/sasl_passwd <<EOF
[localhost]:587 $SMTP_USER:$SMTP_PASS
EOF

postmap /etc/postfix/sasl_passwd

[ ! -f /etc/postfix/main.cf.bak ] && cp /etc/postfix/main.cf /etc/postfix/main.cf.bak

postconf -e "relayhost = [localhost]:587"
postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtp_use_tls = yes"
postconf -e "smtp_tls_security_level = encrypt"
postconf -e "smtp_tls_note_starttls_offer = yes"
postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
postconf -e "smtp_sasl_type = cyrus"
postconf -e "smtp_sasl_path = smtpd"

mkdir -p /etc/sasl2
cat > /etc/sasl2/smtp.conf <<EOF
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: plain login
EOF

echo "$SMTP_PASS" | saslpasswd2 -c -u "$DOMAIN" "$SMTP_USER" -p

systemctl restart saslauthd
systemctl restart postfix

log SUCCESS "Postfix configured with SMTP auth user $SMTP_USER"

log INFO "Installing Docker..."
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com -o get-docker.sh >> "$LOG_FILE" 2>&1
  sh get-docker.sh >> "$LOG_FILE" 2>&1
  rm get-docker.sh
  log SUCCESS "Docker installed"
else
  log INFO "Docker already installed"
fi
systemctl enable --now docker >> "$LOG_FILE" 2>&1

log INFO "Installing Docker Compose plugin..."
if ! dpkg -s docker-compose-plugin >/dev/null 2>&1; then
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg >> "$LOG_FILE" 2>&1
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt update >> "$LOG_FILE" 2>&1
  apt install -y docker-compose-plugin >> "$LOG_FILE" 2>&1
  log SUCCESS "Docker Compose plugin installed"
else
  log INFO "Docker Compose plugin already installed"
fi

log INFO "Cloning or updating Supabase repo..."
mkdir -p /opt/supabase
cd /opt/supabase
if [ -d supabase ]; then
  cd supabase
  git fetch --all >> "$LOG_FILE" 2>&1
  git reset --hard origin/main >> "$LOG_FILE" 2>&1
  cd ..
  log SUCCESS "Supabase repo updated"
else
  git clone https://github.com/supabase/supabase.git --depth=1 >> "$LOG_FILE" 2>&1
  log SUCCESS "Supabase repo cloned"
fi

log INFO "Copying Docker configs..."
cp -r supabase/docker ./docker
cp docker/docker-compose.yml ./
log SUCCESS "Docker configs copied"

log INFO "Creating .env with secrets..."
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
DOCKER_SOCKET_LOCATION=/var/run/docker.sock
POOLER_MAX_CLIENT_CONN=20
POOLER_DEFAULT_POOL_SIZE=10
STUDIO_DEFAULT_ORGANIZATION=default_org
STUDIO_DEFAULT_PROJECT=default_project
JWT_EXPIRY=3600
CERTBOT_EMAIL=$EMAIL
SMTP_USER=$SMTP_USER
SMTP_PASS=$SMTP_PASS
EOF
log SUCCESS ".env created with secrets"

log INFO "Setting up nginx and basic auth..."
htpasswd -cb /etc/nginx/.htpasswd "$DASHBOARD_USERNAME" "$DASHBOARD_PASSWORD" >> "$LOG_FILE" 2>&1

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

nginx -t >> "$LOG_FILE" 2>&1
systemctl reload nginx >> "$LOG_FILE" 2>&1
log SUCCESS "Nginx configured and reloaded"

log INFO "Requesting SSL certificate with certbot..."
if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" >> "$LOG_FILE" 2>&1; then
  log SUCCESS "SSL certificate obtained"
else
  log WARN "SSL certificate issue, check domain/email"
fi

log INFO "Starting Supabase containers..."
docker compose --env-file .env -f docker-compose.yml up -d >> "$LOG_FILE" 2>&1
log SUCCESS "Containers started"

log INFO "Checking container health..."
for container in $(docker compose ps -q); do
  name=$(docker inspect --format='{{.Name}}' "$container" | cut -c2-)
  has_healthcheck=$(docker inspect --format='{{json .State.Health}}' "$container" 2>/dev/null || echo "null")
  if [ "$has_healthcheck" != "null" ]; then
    if ! check_container_health "$name"; then
      log ERROR "Container $name unhealthy"
      exit 1
    fi
  else
    log INFO "Container $name no healthcheck, skipping"
  fi
done

log INFO "All containers healthy"

STORAGE_CONTAINER=$(docker ps --filter "name=storage" --format "{{.Names}}" | head -n1)
if [ -z "$STORAGE_CONTAINER" ]; then
  S3_ACCESS_KEY="not found"
  S3_SECRET_KEY="not found"
else
  S3_ACCESS_KEY=$(docker exec "$STORAGE_CONTAINER" printenv MINIO_ACCESS_KEY || echo "not found")
  S3_SECRET_KEY=$(docker exec "$STORAGE_CONTAINER" printenv MINIO_SECRET_KEY || echo "not found")
fi

EMAIL_BODY=$(cat <<EOF
Supabase installation completed successfully!

Studio URL:         $SITE_URL
API URL:            $SITE_URL
DB URL:             postgres://postgres:$POSTGRES_PASSWORD@localhost:5432/postgres

JWT_SECRET:         $JWT_SECRET
anon key:           $ANON_KEY
service_role key:   $SERVICE_ROLE_KEY

Studio username:    $DASHBOARD_USERNAME
Studio/nginx password: $DASHBOARD_PASSWORD

Domain:             $DOMAIN

S3 Access Key:      $S3_ACCESS_KEY
S3 Secret Key:      $S3_SECRET_KEY
S3 Region:          local

SSL Email:          $EMAIL

SMTP user:          $SMTP_USER
SMTP password:      $SMTP_PASS

Logs file:          $LOG_FILE
EOF
)

send_email_report "Supabase Installation Report for $DOMAIN" "$EMAIL_BODY" "$EMAIL"

log SUCCESS "Installation email sent to $EMAIL"

echo -e "\n----------------------------------------"
echo "$EMAIL_BODY"
echo "----------------------------------------"

exit 0
