# Centralized Nginx Log Monitoring Using Grafana, Loki and Promtail on AWS EC2

## 1. Project Overview

This project demonstrates centralized log monitoring using two AWS EC2 Linux servers.

We install Nginx and Promtail on the first EC2 instance. Promtail collects Nginx access and error logs and forwards them to Loki running on the second EC2 instance.

Grafana is also installed on the second EC2 instance. Grafana connects to Loki and displays collected logs through dashboards.

### Technologies Used

- AWS EC2
- Amazon Linux 2023
- Nginx
- Promtail
- Grafana Loki
- Grafana

## 2. Architecture

```text
                   AWS CLOUD
                       |
                Same VPC / Region
                       |
          ---------------------------
          |                         |
          |                         |
      EC2 SERVER 1              EC2 SERVER 2
   Nginx + Promtail             Loki + Grafana
          |                         |
          |                         |
   Nginx generates             Loki receives
   access/error logs            and stores logs
          |                         |
          v                         |
   Promtail reads                  |
   Nginx log files                 |
          |                         |
          +-------------------------+
              Private IP:3100
              Loki Push API
                       |
                       v
                     LOKI
                       |
                       v
                    GRAFANA
                       |
                       v
               Grafana Dashboard
```

## 3. EC2 Server Details

We created two EC2 instances in the same AWS VPC and region.

| Configuration | EC2-1 | EC2-2 |
|---|---|---|
| Server name | Nginx/Promtail Server | Loki/Grafana Server |
| Software | Nginx + Promtail | Loki + Grafana |
| Private IP | Promtail server private IP | Loki server private IP |
| Ports | 80, 9080 (local) | 3000, 3100 |
| Purpose | Log collection | Log storage and visualization |

## 4. Step 1: Install Nginx and Promtail on EC2-1

Connect to the Nginx/Promtail EC2 server.

Clone the GitHub repository:

```bash
git clone https://github.com/singhranjana-ai/log-monitoring.git
cd log-monitoring
```

Run the installation script:

```bash
sudo bash nginx-promtail.sh
```

The script performs the following tasks:

1. Installs Nginx.
2. Starts and enables the Nginx service.
3. Creates a dedicated Promtail user.
4. Downloads and installs Promtail.
5. Configures Promtail to read Nginx log files.
6. Configures the Loki server destination.
7. Creates the Promtail systemd service.
8. Starts and enables Promtail.

### Nginx Log Files

Nginx generates two important log files.

**Access log:**

```text
/var/log/nginx/access.log
```

It records incoming HTTP requests, client addresses, request methods, status codes and response sizes.

**Error log:**

```text
/var/log/nginx/error.log
```

It records Nginx errors and diagnostic messages.

### Check Nginx Service

```bash
sudo systemctl status nginx
```

### Check Promtail Service

```bash
sudo systemctl status promtail
```

### Check Nginx Logs

```bash
sudo tail -f /var/log/nginx/access.log
```

Generate test requests:

```bash
for i in {1..10}; do
    curl http://localhost
done
```

Expected access log example:

```text
::1 - - [05/Nov/2026:13:38:56 +0000]
"GET / HTTP/1.1" 200 896 "-" "curl/8.21.0" "-"
```

Explanation:

- `::1` - Localhost IPv6 address.
- `GET /` - HTTP GET request to the homepage.
- `200` - Successful HTTP response.
- `896` - Response size in bytes.
- `curl/8.21.0` - Client making the request.

## 5. Step 2: Configure Promtail to Send Logs to Loki

This is an important part of the project.

Promtail runs on EC2-1, while Loki runs on EC2-2.

Therefore, Promtail needs the **private IP address of the Loki/Grafana server**.

### Promtail Configuration

The Promtail configuration contains:

```yaml
clients:
  - url: http://LOKI_PRIVATE_IP:3100/loki/api/v1/push
```

Replace `LOKI_PRIVATE_IP` with the actual private IP address of your Loki/Grafana EC2 server.

### What does this configuration mean?

- `LOKI_PRIVATE_IP` - Private IP of the second EC2 server.
- `3100` - Loki HTTP listening port.
- `/loki/api/v1/push` - Loki log ingestion API.

### How does communication work?

1. Nginx generates access and error logs.
2. Promtail reads the Nginx log files.
3. Promtail sends the logs over HTTP to the Loki server.
4. Loki receives and stores the logs.
5. Grafana queries Loki to display the logs.

### Why use the private IP?

Both EC2 instances are in the same VPC.

They can communicate using private IP addresses without sending internal log traffic over the public internet.

### Important Promtail Configuration

```yaml
server:
  http_listen_address: 127.0.0.1
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://LOKI_PRIVATE_IP:3100/loki/api/v1/push

scrape_configs:
  - job_name: nginx
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx
          host: nginx-server
          __path__: /var/log/nginx/*.log
```

### Important Configuration Explanation

| Parameter | Purpose |
|---|---|
| `positions` | Tracks how much of each log file Promtail has read |
| `clients` | Defines the Loki destination |
| `job_name` | Identifies the log collection job |
| `job: nginx` | Adds a label to collected logs |
| `__path__` | Specifies which log files Promtail reads |

Promtail automatically retries when Loki is temporarily unavailable.

## 6. Step 3: Install Loki and Grafana on EC2-2

Connect to the Loki/Grafana EC2 server.

Clone the repository:

```bash
git clone https://github.com/singhranjana-ai/log-monitoring.git
cd log-monitoring
```

Run the installation script:

```bash
sudo bash grafana-loki.sh
```

The script performs the following tasks:

1. Downloads and installs Loki.
2. Creates the Loki system user.
3. Creates Loki configuration and storage directories.
4. Configures Loki to listen on port 3100.
5. Creates a Loki systemd service.
6. Installs Grafana.
7. Configures Loki as a Grafana data source.
8. Starts Loki and Grafana.
9. Checks Loki readiness and Grafana health.

### Check Loki Service

```bash
sudo systemctl status loki
```

### Check Grafana Service

```bash
sudo systemctl status grafana-server
```

### Check Loki Readiness

```bash
curl http://localhost:3100/ready
```

Expected output:

```text
ready
```

### Check Grafana Health

```bash
curl http://localhost:3000/api/health
```

Expected response:

```json
{
  "database": "ok",
  "version": "13.3.0"
}
```

## 7. Step 4: Understand Promtail, Loki and Grafana Communication

There are two separate connections in this architecture.

### Connection 1: Promtail to Loki

Promtail runs on EC2-1 and Loki runs on EC2-2.

Therefore, Promtail uses the private IP of the Loki server.

```text
Promtail Server
      |
      |
      v
http://LOKI_PRIVATE_IP:3100/loki/api/v1/push
      |
      v
Loki Server
```

### Connection 2: Grafana to Loki

Grafana and Loki are installed on the same EC2-2 server.

Therefore, Grafana uses localhost:

```text
http://localhost:3100
```

The Grafana data source configuration:

```yaml
apiVersion: 1

datasources:
  - name: Loki
    uid: loki
    type: loki
    access: proxy
    url: http://localhost:3100
    isDefault: true
    editable: true
```

**Important:** We do not need to enter the Loki server private IP in Grafana because Grafana and Loki are running on the same server.

## 8. Step 5: Configure AWS Security Groups

We need to allow communication between both EC2 instances.

### EC2-1: Nginx/Promtail Security Group

| Type | Port | Source |
|---|---|---|
| SSH | 22 | My IP |
| HTTP | 80 | My IP |

### EC2-2: Loki/Grafana Security Group

| Type | Port | Source |
|---|---|---|
| SSH | 22 | My IP |
| Custom TCP | 3000 | My IP |
| Custom TCP | 3100 | Nginx/Promtail EC2 Security Group |

**Security recommendation:**

Do not expose Loki port 3100 to the entire internet.

Allow only the Nginx/Promtail EC2 security group to access it.

## 9. Step 6: Open Grafana

Open the Grafana URL using the public IP of the Loki/Grafana EC2 server:

```text
http://LOKI_SERVER_PUBLIC_IP:3000
```

Default login:

```text
Username: admin
Password: admin
```

Change the default password when prompted.

The Loki data source is provisioned automatically by our installation script.

## 10. Step 7: Verify Logs in Grafana Explore

Navigate to:

```text
Grafana → Explore → Loki
```

Select the Loki data source.

Enter this LogQL query:

```logql
{job="nginx"}
```

Click **Run query**.

Expected output:

```text
::1 - - [05/Nov/2026:13:38:56 +0000]
"GET / HTTP/1.1" 200 896 "-" "curl/8.21.0" "-"
```

This confirms that:

- Nginx generated the log.
- Promtail collected the log.
- Promtail forwarded the log to Loki.
- Loki stored the log.
- Grafana successfully queried Loki.

## 11. Step 8: Generate More Nginx Logs

Connect to EC2-1.

Generate successful requests:

```bash
for i in {1..10}; do
    curl http://localhost
done
```

Generate a 404 error:

```bash
curl http://localhost/invalid-page
```

Generate repeated requests:

```bash
for i in {1..50}; do
    curl -s http://localhost > /dev/null
done
```

Return to Grafana Explore and run:

```logql
{job="nginx"}
```

You should see the newly generated requests.

## 12. Step 9: Useful LogQL Queries

LogQL is the query language used by Loki.

### 1. Display All Nginx Logs

```logql
{job="nginx"}
```

Output: All collected Nginx log entries.

### 2. Display Successful HTTP Requests

```logql
{job="nginx"} |~ "\" 2[0-9][0-9] "
```

Output: HTTP 2xx responses.

### 3. Display Client Errors

```logql
{job="nginx"} |~ "\" 4[0-9][0-9] "
```

Output: HTTP 4xx responses, such as 404.

### 4. Display Server Errors

```logql
{job="nginx"} |~ "\" 5[0-9][0-9] "
```

Output: HTTP 5xx responses.

### 5. Search for Error Messages

```logql
{job="nginx"} |= "error"
```

Output: Log lines containing the word error.

### 6. Count Total Requests in the Last Five Minutes

```logql
sum(count_over_time({job="nginx"}[5m]))
```

Output: Total matching log entries over the last five minutes.

Use this query in a Grafana Stat visualization.

### 7. Count HTTP 404 Responses in Five Minutes

```logql
sum(count_over_time({job="nginx"} |~ "\" 404 "[5m]))
```

Output: Number of 404 responses in the last five minutes.

### 8. Count HTTP 500 Responses in Five Minutes

```logql
sum(count_over_time({job="nginx"} |~ "\" 500 "[5m]))
```

Output: Number of HTTP 500 responses in the last five minutes.

## 13. Step 10: Create a Grafana Dashboard

Navigate to:

```text
Grafana → Dashboards → New → New dashboard
```

Select Auto grid.

Click Add visualization and choose Loki as the data source.

Create the following panels:

| Panel name | Query | Visualization |
|---|---|---|
| Total Nginx Requests | `sum(count_over_time({job="nginx"}[5m]))` | Stat |
| HTTP 404 Count | `sum(count_over_time({job="nginx"} \|~ "\" 404 "[5m]))` | Stat |
| HTTP 500 Count | `sum(count_over_time({job="nginx"} \|~ "\" 500 "[5m]))` | Stat |
| Successful Requests | `sum(count_over_time({job="nginx"} \|~ "\" 2[0-9][0-9] "[5m]))` | Stat |
| All Nginx Logs | `{job="nginx"}` | Logs |
| Nginx Error Logs | `{job="nginx"} \|= "error"` | Logs |

### What can we monitor using these panels?

1. Total number of Nginx requests.
2. Successful HTTP responses.
3. Client-side HTTP errors.
4. Server-side HTTP errors.
5. Live Nginx access logs.
6. Nginx error messages.

For count panels, use Stat visualization.

For live log entries, use Logs visualization.

For request trends over time, use Time series visualization.

**Note:** These queries count matching log entries. They do not measure CPU, RAM or disk utilization.

## 14. Logs vs Metrics

Logs and metrics are different types of monitoring data.

| Tool | Purpose |
|---|---|
| Promtail | Collects and forwards logs |
| Loki | Stores and queries logs |
| Prometheus | Collects and stores metrics |
| Node Exporter | Exposes Linux server metrics |
| Grafana | Visualizes logs and metrics |

If we want to monitor CPU, memory, disk and network utilization, we can add Prometheus and Node Exporter.

Grafana can use both Loki and Prometheus as data sources in the same dashboard.

## 15. Troubleshooting

### Problem 1: Loki Connection Refused

On the Loki/Grafana server:

```bash
sudo systemctl status loki
```

Check port 3100:

```bash
sudo ss -lntp | grep 3100
```

Check readiness:

```bash
curl http://localhost:3100/ready
```

### Problem 2: Promtail Cannot Send Logs

On the Nginx/Promtail server:

```bash
sudo systemctl status promtail
```

Check Promtail logs:

```bash
sudo journalctl -u promtail -n 50 --no-pager
```

### Problem 3: Grafana Shows No Logs

Check:

1. Loki service is active.
2. Promtail service is active.
3. Promtail has the correct Loki server private IP.
4. EC2 security group allows TCP 3100 from the Promtail server security group.
5. Grafana Loki data source is configured correctly.
6. The Grafana query uses the correct label: `{job="nginx"}`.

## 16. Final Project Result

We successfully implemented centralized Nginx log monitoring using two AWS EC2 instances.

Final workflow:

```text
EC2-1: Nginx/Promtail Server
             |
             v
    Nginx Access/Error Logs
             |
             v
          Promtail
             |
             v
     Loki Server Private IP
             |
             v
      EC2-2: Loki Server
             |
             v
        Loki Storage
             |
             v
       Grafana Data Source
             |
             v
     Grafana Explore/Dashboard
```

This project demonstrates how logs from one Linux server can be collected centrally, stored and visualized using open-source monitoring tools.

---

## GitHub Repository

https://github.com/singhranjana-ai/log-monitoring

### Scripts in This Repository

- `nginx-promtail.sh` - Installs and configures Nginx and Promtail.
- `grafana-loki.sh` - Installs and configures Loki and Grafana.

### Learning Outcomes

- AWS EC2 deployment.
- Private IP communication between EC2 instances.
- AWS Security Group configuration.
- Linux service management using systemd.
- Nginx access and error log monitoring.
- Promtail log collection and forwarding.
- Loki log ingestion and storage.
- LogQL queries.
- Grafana Explore and dashboard creation.

### Production Note

This project uses Promtail for learning and practical understanding. Promtail reached end of life in March 2026. For new production deployments, consider Grafana Alloy.
