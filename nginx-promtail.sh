
#!/bin/bash

# ==========================================
# NGINX + PROMTAIL INSTALLATION
# OS: Amazon Linux 2023
# ==========================================

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo bash nginx-promtail.sh"
    exit 1
fi

PROMTAIL_VERSION="3.5.7"

echo "Installing Nginx and Promtail..."

# 1. Install required packages
dnf install -y nginx curl unzip acl

# 2. Start Nginx
systemctl enable --now nginx

# 3. Create Promtail user
if ! id promtail >/dev/null 2>&1; then
    useradd --system --no-create-home \
        --shell /sbin/nologin promtail
fi

# 4. Give Promtail permission to read Nginx logs
setfacl -m u:promtail:rx /var/log/nginx
setfacl -m d:u:promtail:rx /var/log/nginx

# Apply access to existing log files
find /var/log/nginx -type f \
    -exec setfacl -m u:promtail:r {} \;

# 5. Detect CPU architecture
ARCH=$(uname -m)

case "$ARCH" in
    x86_64) PROMTAIL_ARCH="amd64" ;;
    aarch64) PROMTAIL_ARCH="arm64" ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# 6. Download Promtail
cd /tmp

curl -fL \
"https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-${PROMTAIL_ARCH}.zip" \
-o promtail.zip

unzip -o promtail.zip -d /tmp/promtail-install

install -m 0755 \
"/tmp/promtail-install/promtail-linux-${PROMTAIL_ARCH}" \
/usr/local/bin/promtail

# 7. Ask for Loki private IP
echo ""
read -r -p "Enter Loki EC2 PRIVATE IP: " LOKI_SERVER_IP

if [[ ! "$LOKI_SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid IP address"
    exit 1
fi

# 8. Create Promtail directories
mkdir -p /etc/promtail
mkdir -p /var/lib/promtail

# 9. Configure Promtail
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

chown -R promtail:promtail /var/lib/promtail
chmod 750 /etc/promtail
chmod 640 /etc/promtail/promtail.yaml

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
echo "===================================="
echo " NGINX + PROMTAIL INSTALLED"
echo "===================================="

systemctl --no-pager status nginx || true
systemctl --no-pager status promtail || true

echo ""
echo "Nginx website: http://YOUR_PUBLIC_IP"
echo "Promtail endpoint: http://localhost:9080/ready"
