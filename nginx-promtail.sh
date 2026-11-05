
#!/bin/bash

# =====================================================
# NGINX + PROMTAIL INSTALLATION
# OS: Amazon Linux 2023
# Purpose: Collect Nginx logs and send them to Loki
# =====================================================

set -Eeuo pipefail

PROMTAIL_VERSION="3.5.7"

# Check root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Run this script as root."
    echo "Command: sudo bash nginx-promtail.sh"
    exit 1
fi

echo "=========================================="
echo " NGINX + PROMTAIL INSTALLATION STARTED"
echo "=========================================="

# 1. Install packages
echo "[1/10] Installing required packages..."

dnf install -y nginx unzip acl

# Amazon Linux 2023 normally provides curl-minimal.
# Do not install the conflicting full curl package.
if ! command -v curl >/dev/null 2>&1; then
    dnf install -y curl-minimal
fi

# 2. Start Nginx
echo "[2/10] Starting Nginx..."

systemctl enable --now nginx

# 3. Create Promtail user
echo "[3/10] Creating Promtail user..."

if ! id promtail >/dev/null 2>&1; then
    useradd --system --no-create-home \
        --shell /sbin/nologin promtail
fi

# 4. Configure Nginx log permissions
echo "[4/10] Configuring log permissions..."

mkdir -p /var/log/nginx

setfacl -m u:promtail:--x /var/log
setfacl -m u:promtail:rx /var/log/nginx
setfacl -m d:u:promtail:rx /var/log/nginx

find /var/log/nginx -type f \
    -exec setfacl -m u:promtail:r {} \;

# 5. Detect architecture
echo "[5/10] Detecting server architecture..."

ARCH=$(uname -m)

case "$ARCH" in
    x86_64)
        PROMTAIL_ARCH="amd64"
        ;;
    aarch64)
        PROMTAIL_ARCH="arm64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# 6. Download Promtail
echo "[6/10] Downloading Promtail..."

cd /tmp

curl -fL --retry 3 \
"https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-${PROMTAIL_ARCH}.zip" \
-o promtail.zip

mkdir -p /tmp/promtail-install

unzip -o promtail.zip -d /tmp/promtail-install

install -m 0755 \
"/tmp/promtail-install/promtail-linux-${PROMTAIL_ARCH}" \
/usr/local/bin/promtail

/usr/local/bin/promtail --version

# 7. Get Loki private IP
echo ""
echo "Enter the PRIVATE IP of your Loki EC2 server."
read -r -p "Loki Private IP: " LOKI_SERVER_IP

# Validate private IPv4 address
if [[ ! "$LOKI_SERVER_IP" =~ ^(10\.([0-9]{1,3}\.){2}[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.([0-9]{1,3}\.)[0-9]{1,3}|192\.168\.([0-9]{1,3}\.)[0-9]{1,3})$ ]]; then
    echo "ERROR: Enter a valid private IPv4 address."
    exit 1
fi

# 8. Create directories
echo "[8/10] Creating Promtail directories..."

mkdir -p /etc/promtail
mkdir -p /var/lib/promtail

# 9. Create Promtail configuration
echo "[9/10] Creating Promtail configuration..."

cat > /etc/promtail/promtail.yaml <<EOF
server:
  http_listen_address: 127.0.0.1
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://${LOKI_SERVER_IP}:3100/loki/api/v1/push

scrape_configs:
  - job_name: nginx
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx
          host: nginx-server
          __path__: /var/log/nginx/*.log
EOF

chown root:promtail /etc/promtail
chown root:promtail /etc/promtail/promtail.yaml

chmod 750 /etc/promtail
chmod 640 /etc/promtail/promtail.yaml

chown -R promtail:promtail /var/lib/promtail
chmod 750 /var/lib/promtail

# 10. Create systemd service
echo "[10/10] Creating Promtail service..."

cat > /etc/systemd/system/promtail.service <<'EOF'
[Unit]
Description=Promtail Log Collector
After=network-online.target nginx.service
Wants=network-online.target

[Service]
Type=simple
User=promtail
Group=promtail
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start Promtail
systemctl daemon-reload
systemctl enable --now promtail

# Final verification
echo ""
echo "=========================================="
echo " INSTALLATION VERIFICATION"
echo "=========================================="

echo ""
echo "Nginx:"
systemctl is-active nginx || true

echo ""
echo "Promtail:"
systemctl is-active promtail || true

echo ""
echo "Promtail version:"
/usr/local/bin/promtail --version

echo ""
echo "Promtail configuration:"
echo "/etc/promtail/promtail.yaml"

echo ""
echo "Loki destination:"
echo "http://${LOKI_SERVER_IP}:3100/loki/api/v1/push"

echo ""
echo "=========================================="
echo " NGINX + PROMTAIL SETUP FINISHED"
echo "=========================================="
