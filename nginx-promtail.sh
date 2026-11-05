
#!/bin/bash

# ==================================================
# NGINX + PROMTAIL INSTALLATION
# OS: Amazon Linux 2023
# ==================================================

set -euo pipefail

PROMTAIL_VERSION="3.5.7"

# Check root permission
if [ "$EUID" -ne 0 ]; then
    echo "Please run: sudo bash nginx-promtail.sh"
    exit 1
fi

echo "=========================================="
echo " Installing Nginx and Promtail"
echo "=========================================="

# 1. Install required packages
# Amazon Linux 2023 already provides curl-minimal.
dnf install -y nginx unzip acl

# Verify curl is available
if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl command not found"
    exit 1
fi

# 2. Start Nginx
systemctl enable --now nginx

echo "Nginx installation completed."

# 3. Create Promtail user
if ! id promtail >/dev/null 2>&1; then
    useradd --system --no-create-home \
        --shell /sbin/nologin promtail
fi

# 4. Give Promtail permission to read Nginx logs
mkdir -p /var/log/nginx

setfacl -m u:promtail:rx /var/log
setfacl -m u:promtail:rx /var/log/nginx
setfacl -m d:u:promtail:rx /var/log/nginx

# Give access to existing log files
find /var/log/nginx -type f \
    -exec setfacl -m u:promtail:r {} \;

# 5. Detect CPU architecture
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
cd /tmp

echo "Downloading Promtail version ${PROMTAIL_VERSION}..."

curl -fL --retry 3 \
"https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-${PROMTAIL_ARCH}.zip" \
-o promtail.zip

# Extract Promtail
mkdir -p /tmp/promtail-install

unzip -o promtail.zip -d /tmp/promtail-install

# Install binary
install -m 0755 \
"/tmp/promtail-install/promtail-linux-${PROMTAIL_ARCH}" \
/usr/local/bin/promtail

# Verify installation
/usr/local/bin/promtail --version

# 7. Ask for Loki private IP
echo ""
read -r -p "Enter Loki EC2 PRIVATE IP: " LOKI_SERVER_IP

if [[ ! "$LOKI_SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "ERROR: Invalid IP address"
    exit 1
fi

# 8. Create Promtail directories
mkdir -p /etc/promtail
mkdir -p /var/lib/promtail

# 9. Create Promtail configuration
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

# Allow Promtail service to read its configuration
chown root:promtail /etc/promtail/promtail.yaml
chmod 640 /etc/promtail/promtail.yaml

chown -R promtail:promtail /var/lib/promtail
chmod 750 /etc/promtail

# 10. Create Promtail systemd service
cat > /etc/systemd/system/promtail.service <<'EOF'
[Unit]
Description=Promtail Log Collector
After=network-online.target nginx.service
Wants=network-online.target

[Service]
User=promtail
Group=promtail
Type=simple
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 11. Start Promtail
systemctl daemon-reload
systemctl enable --now promtail

echo ""
echo "=========================================="
echo " NGINX + PROMTAIL INSTALLATION COMPLETED"
echo "=========================================="

echo ""
echo "Nginx status:"
systemctl is-active nginx

echo ""
echo "Promtail status:"
systemctl is-active promtail

echo ""
echo "Nginx website: http://YOUR_PUBLIC_IP"
echo "Promtail local endpoint: http://localhost:9080/ready"
echo ""
echo "Promtail is configured to send logs to:"
echo "http://${LOKI_SERVER_IP}:3100/loki/api/v1/push"
