#!/usr/bin/env bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)."
  exit 1
fi

echo "=== RemnaNode + SelfSteal Setup ==="

# --- Docker ---
if ! command -v docker &>/dev/null; then
  echo ">>> Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker 2>/dev/null || true
else
  echo ">>> Docker already installed."
fi

# --- Domain ---
read -r -p "Enter your domain (e.g. steel.domain.com): " DOMAIN
DOMAIN="${DOMAIN:-steel.domain.com}"

# ========== RemnaNode ==========
echo ">>> Setting up RemnaNode..."
mkdir -p /opt/remnanode

if [ ! -f /opt/remnanode/docker-compose.yml ]; then
  echo ""
  echo "=============================================="
  echo "  Open another terminal and run:"
  echo "    nano /opt/remnanode/docker-compose.yml"
  echo "  Paste your docker-compose content, save,"
  echo "  then come back here and press ENTER."
  echo "=============================================="
  read -r -p "Press ENTER when docker-compose.yml is ready..."
fi

cd /opt/remnanode
docker compose up -d

# ========== SelfSteel / Caddy ==========
echo ">>> Setting up SelfSteel (Caddy reverse proxy)..."
mkdir -p /opt/selfsteel /opt/html

# --- .env ---
cat > /opt/selfsteel/.env <<EOF
SELF_STEAL_DOMAIN=$DOMAIN
SELF_STEAL_PORT=8443
EOF

# --- Caddyfile ---
cat > /opt/selfsteel/Caddyfile <<'CADDYEOF'
{
    https_port {$SELF_STEAL_PORT}
    default_bind 127.0.0.1
    servers {
        listener_wrappers {
            proxy_protocol {
                allow 127.0.0.1/32
            }
            tls
        }
    }
    auto_https disable_redirects
}

http://{$SELF_STEAL_DOMAIN} {
    bind 0.0.0.0
    redir https://{$SELF_STEAL_DOMAIN}{uri} permanent
}

https://{$SELF_STEAL_DOMAIN} {
    root * /var/www/html
    try_files {path} /index.html
    file_server
}

:{$SELF_STEAL_PORT} {
    tls internal
    respond 204
}

:80 {
    bind 0.0.0.0
    respond 204
}
CADDYEOF

# --- docker-compose.yml ---
cat > /opt/selfsteel/docker-compose.yml <<'COMPOSEEOF'
services:
  caddy:
    image: caddy:latest
    container_name: caddy-remnawave
    restart: unless-stopped
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ../html:/var/www/html
      - ./logs:/var/log/caddy
      - caddy_data_selfsteal:/data
      - caddy_config_selfsteal:/config
    env_file:
      - .env
    network_mode: "host"

volumes:
  caddy_data_selfsteal:
  caddy_config_selfsteal:
COMPOSEEOF

# --- html ---
cat > /opt/html/index.html <<'HTMLEOF'
<!doctype html><meta charset="utf-8"><title>Selfsteal</title><h1>It works.</h1>
HTMLEOF

# --- up ---
cd /opt/selfsteel
docker compose up -d

echo ""
echo "=== Done ==="
echo "RemnaNode: /opt/remnanode"
echo "SelfSteel: /opt/selfsteel"
echo "Domain:    $DOMAIN"
echo "Port:      8443"
