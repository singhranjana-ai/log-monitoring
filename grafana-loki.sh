
#!/bin/bash

# =====================================================
# GRAFANA + LOKI INSTALLATION
# OS: Amazon Linux 2023
# Purpose: Receive and visualize Nginx logs from Promtail
# =====================================================

set -Eeuo pipefail

LOKI_VERSION="3.7.9"

# 1. Check root permission
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Run as root."
    echo "Command: sudo bash grafana-loki.sh"
    exit 1
fi

echo "=========================================="
echo " GRAFANA + LOKI INSTALLATION STARTED"
echo "=========================================="

# 2. Install required packages
echo "[1/10] Installing dependencies..."

dnf install -y unzip

# Amazon Linux 2023 generally includes curl-minimal.
# Do not install the conflicting full curl package.
if ! command -v curl >/dev/null 2>&1; then
    dnf install -y curl-minimal
fi

# 3. Detect architecture
echo "[2/10] Detecting architecture..."

ARCH=$(uname -m)

case "$ARCH" in
    x86_64)
        LOKI_ARCH="amd64"
        ;;
    aarch64)
        LOKI_ARCH="arm64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# 4. Create Loki user and directories
echo "[3/10] Creating Loki user and directories..."

if ! id loki >/dev/null 2>&1; then
    useradd --system --home-dir /var/lib/loki \
        --shell /sbin/nologin loki
fi

mkdir -p /etc/loki
mkdir -p /var/lib/loki/chunks
mkdir -p /var/lib/loki/rules
mkdir -p /var/lib/loki/compactor

# 5. Download and install Loki
echo "[4/10] Downloading Loki ${LOKI_VERSION}..."

cd /tmp

curl -fL --retry 3 \
"https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-${LOKI_ARCH}.zip" \
-o loki.zip

mkdir -p /tmp/loki-install

unzip -o loki.zip -d /tmp/loki-install

install -m 0755 \
"/tmp/loki-install/loki-linux-${LOKI_ARCH}" \
/usr/local/bin/loki

/usr/local/bin/loki --version

# 6. Create Loki configuration
echo "[5/10] Creating Loki configuration..."

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

# 7. Create Loki systemd service
echo "[6/10] Creating Loki service..."

cat > /etc/systemd/system/loki.service <<'EOF'
[Unit]
Description=Grafana Loki Log Storage
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=loki
Group=loki
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki.yaml
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# 8. Configure Grafana repository
echo "[7/10] Configuring Grafana repository..."

curl -fL --retry 3 \
https://rpm.grafana.com/gpg.key \
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
echo "[8/10] Installing Grafana..."

dnf install -y grafana

# Configure Loki as Grafana data source
echo "[9/10] Configuring Grafana Loki data source..."

mkdir -p /etc/grafana/provisioning/datasources

cat > /etc/grafana/provisioning/datasources/loki.yaml <<'EOF'
apiVersion: 1

datasources:
  - name: Loki
    uid: loki
    type: loki
    access: proxy
    url: http://localhost:3100
    isDefault: true
    editable: true
EOF

# 10. Start Loki and Grafana
echo "[10/10] Starting Loki and Grafana..."

systemctl daemon-reload

systemctl enable --now loki

# Check Loki readiness
echo ""
echo "Waiting for Loki to become ready..."

LOKI_READY=0

for i in {1..30}; do
    if curl -fsS http://localhost:3100/ready >/dev/null; then
        LOKI_READY=1
        break
    fi

    sleep 2
done

if [ "$LOKI_READY" -ne 1 ]; then
    echo "ERROR: Loki did not become ready."
    echo "Loki service logs:"
    journalctl -u loki -n 50 --no-pager || true
    exit 1
fi

echo "Loki is READY."

# Start Grafana
systemctl enable --now grafana-server

# Check Grafana service
if ! systemctl is-active --quiet grafana-server; then
    echo "ERROR: Grafana failed to start."
    journalctl -u grafana-server -n 50 --no-pager || true
    exit 1
fi

# Final verification
echo ""
echo "Checking Grafana HTTP endpoint..."

GRAFANA_READY=0

for i in {1..30}; do
    if curl -fsS http://localhost:3000/api/health >/dev/null; then
        GRAFANA_READY=1
        break
    fi

    sleep 2
done

if [ "$GRAFANA_READY" -ne 1 ]; then
    echo "ERROR: Grafana HTTP endpoint is not responding."
    journalctl -u grafana-server -n 50 --no-pager || true
    exit 1
fi

echo ""
echo "=========================================="
echo " GRAFANA + LOKI INSTALLATION SUCCESSFUL"
echo "=========================================="

echo ""
echo "Loki version:"
/usr/local/bin/loki --version

echo ""
echo "Loki service:"
systemctl is-active loki

echo ""
echo "Grafana service:"
systemctl is-active grafana-server

echo ""
echo "Loki readiness:"
curl -fsS http://localhost:3100/ready

echo ""
echo "Grafana health:"
curl -fsS http://localhost:3000/api/health

echo ""
echo "Grafana URL: http://YOUR_PUBLIC_IP:3000"
echo "Default login: admin / admin"
echo "Loki URL: http://YOUR_PRIVATE_IP:3100"

echo ""
echo "IMPORTANT: Restrict Loki port 3100 using AWS Security Groups."
echo "Allow only the Nginx/Promtail EC2 security group."
