
#!/bin/bash

# ==========================================
# GRAFANA + LOKI INSTALLATION
# OS: Amazon Linux 2023
# ==========================================

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo bash grafana-loki.sh"
    exit 1
fi

LOKI_VERSION="3.7.9"

echo "Installing Loki and Grafana..."

# 1. Install dependencies
dnf install -y curl unzip

# 2. Detect CPU architecture
ARCH=$(uname -m)

case "$ARCH" in
    x86_64) LOKI_ARCH="amd64" ;;
    aarch64) LOKI_ARCH="arm64" ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# 3. Create Loki user
if ! id loki >/dev/null 2>&1; then
    useradd --system --home-dir /var/lib/loki \
        --shell /sbin/nologin loki
fi

# 4. Create Loki directories
mkdir -p /etc/loki
mkdir -p /var/lib/loki/chunks
mkdir -p /var/lib/loki/rules
mkdir -p /var/lib/loki/compactor

# 5. Download Loki
cd /tmp

curl -fL \
"https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-${LOKI_ARCH}.zip" \
-o loki.zip

unzip -o loki.zip -d /tmp/loki-install

install -m 0755 \
"/tmp/loki-install/loki-linux-${LOKI_ARCH}" \
/usr/local/bin/loki

# 6. Configure Loki
cat > /etc/loki/loki.yaml <<'EOF'
auth_enabled: false

server:
  http_listen_address: 0.0.0.0
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: "2024-04-01"
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

compactor:
  working_directory: /var/lib/loki/compactor
  delete_request_store: filesystem

limits_config:
  allow_structured_metadata: true

analytics:
  reporting_enabled: false
EOF

chown -R loki:loki /etc/loki /var/lib/loki

# 7. Create Loki service
cat > /etc/systemd/system/loki.service <<'EOF'
[Unit]
Description=Grafana Loki
After=network-online.target
Wants=network-online.target

[Service]
User=loki
Group=loki
Type=simple
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 8. Add Grafana repository
curl -fsSL https://rpm.grafana.com/gpg.key \
-o /tmp/grafana-gpg.key

rpm --import /tmp/grafana-gpg.key

cat > /etc/yum.repos.d/grafana.repo <<'EOF'
[grafana]
name=Grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
EOF

# 9. Install Grafana
dnf install -y grafana

# 10. Configure Loki data source in Grafana
mkdir -p /etc/grafana/provisioning/datasources

cat > /etc/grafana/provisioning/datasources/loki.yaml <<'EOF'
apiVersion: 1

datasources:
  - name: Loki
    uid: loki
    type: loki
    access: proxy
    url: http://localhost:3100
    isDefault: false
    editable: true
EOF

# 11. Start Loki and Grafana
systemctl daemon-reload

systemctl enable --now loki
systemctl enable --now grafana-server

# 12. Verify Loki
echo ""
echo "Checking Loki readiness..."

for i in {1..30}; do
    if curl -fsS http://localhost:3100/ready; then
        echo ""
        break
    fi
    sleep 2
done

echo ""
echo "===================================="
echo " GRAFANA + LOKI INSTALLED"
echo "===================================="

systemctl --no-pager status loki || true
systemctl --no-pager status grafana-server || true

echo ""
echo "Grafana URL: http://YOUR_PUBLIC_IP:3000"
echo "Default login: admin / admin"
echo "Loki URL: http://YOUR_PRIVATE_IP:3100"
