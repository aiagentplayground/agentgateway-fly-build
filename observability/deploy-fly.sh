#!/bin/bash
# Deploy AgentGateway with Full Observability Stack to Fly.io
#
# This deploys:
#   - AgentGateway (LLM proxy with metrics + tracing)
#   - Grafana (dashboards)
#   - Prometheus (metrics)  - runs as sidecar via fly.toml
#
# Prerequisites:
#   - flyctl installed: curl -L https://fly.io/install.sh | sh
#   - Logged in: fly auth login
#
# Usage:
#   ./deploy-fly.sh                    # Interactive prompts
#   ./deploy-fly.sh my-gateway sk-xxx  # With args

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     AgentGateway + Observability Stack Deployment            ║"
echo "║     Fly.io Edition                                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check flyctl
if ! command -v fly &> /dev/null; then
    echo -e "${RED}Error: flyctl not installed${NC}"
    echo "Install with: curl -L https://fly.io/install.sh | sh"
    exit 1
fi

# Check auth
if ! fly auth whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged in to Fly.io${NC}"
    echo "Run: fly auth login"
    exit 1
fi

# Get app name
APP_NAME="${1:-}"
if [ -z "$APP_NAME" ]; then
    read -p "Enter app name (default: agentgateway): " APP_NAME
    APP_NAME="${APP_NAME:-agentgateway}"
fi

# Get OpenAI API key
OPENAI_KEY="${2:-}"
if [ -z "$OPENAI_KEY" ]; then
    read -sp "Enter your OpenAI API key: " OPENAI_KEY
    echo
fi

if [ -z "$OPENAI_KEY" ]; then
    echo -e "${RED}Error: OpenAI API key is required${NC}"
    exit 1
fi

# Optional Anthropic key
ANTHROPIC_KEY="${3:-}"
if [ -z "$ANTHROPIC_KEY" ]; then
    read -sp "Enter Anthropic API key (optional, press Enter to skip): " ANTHROPIC_KEY
    echo
fi

echo ""
echo -e "${YELLOW}Deploying with:${NC}"
echo "  App name: $APP_NAME"
echo "  Region: iad (US East)"
echo ""

# Create fly.toml for the stack
cat > fly-observability.toml << 'FLYTOML'
# AgentGateway with Observability - Fly.io Config

app = "APP_NAME_PLACEHOLDER"
primary_region = "iad"

[build]
  dockerfile = "Dockerfile.observability"

[http_service]
  internal_port = 3000
  force_https = true
  auto_stop_machines = "suspend"
  auto_start_machines = true
  min_machines_running = 1
  processes = ["app"]

  [http_service.concurrency]
    type = "connections"
    hard_limit = 100
    soft_limit = 80

# Grafana on port 3001
[[services]]
  internal_port = 3001
  protocol = "tcp"
  [[services.ports]]
    handlers = ["tls", "http"]
    port = 3001

# Prometheus metrics (internal)
[[services]]
  internal_port = 9090
  protocol = "tcp"
  [[services.ports]]
    handlers = ["tls", "http"]
    port = 9090

[[vm]]
  memory = "1gb"
  cpu_kind = "shared"
  cpus = 1

[env]
  GF_SECURITY_ADMIN_USER = "admin"
  GF_USERS_ALLOW_SIGN_UP = "false"
  GF_SERVER_HTTP_PORT = "3001"
FLYTOML

# Replace placeholder
sed -i "s/APP_NAME_PLACEHOLDER/$APP_NAME/g" fly-observability.toml

# Create Dockerfile for full stack
cat > Dockerfile.observability << 'DOCKERFILE'
FROM debian:bookworm-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    supervisor \
    adduser \
    libfontconfig1 \
    musl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install AgentGateway
RUN curl -sL https://raw.githubusercontent.com/agentgateway/agentgateway/refs/heads/main/common/scripts/get-agentgateway | bash \
    && mv /root/.agentgateway/bin/agentgateway /usr/local/bin/

# Install Prometheus
RUN wget -q https://github.com/prometheus/prometheus/releases/download/v2.48.0/prometheus-2.48.0.linux-amd64.tar.gz \
    && tar xzf prometheus-2.48.0.linux-amd64.tar.gz \
    && mv prometheus-2.48.0.linux-amd64/prometheus /usr/local/bin/ \
    && mv prometheus-2.48.0.linux-amd64/promtool /usr/local/bin/ \
    && rm -rf prometheus-*

# Install Grafana
RUN wget -q https://dl.grafana.com/oss/release/grafana_10.2.2_amd64.deb \
    && dpkg -i grafana_10.2.2_amd64.deb \
    && rm grafana_10.2.2_amd64.deb

# Create directories
RUN mkdir -p /etc/agentgateway /etc/prometheus /var/lib/prometheus /var/lib/grafana

# Copy configurations
COPY agentgateway-config.yaml /etc/agentgateway/config.yaml
COPY prometheus/prometheus.yml /etc/prometheus/prometheus.yml
COPY grafana/provisioning /etc/grafana/provisioning

# Update Prometheus config for localhost
RUN sed -i 's/agentgateway:15020/localhost:15020/g' /etc/prometheus/prometheus.yml

# Supervisor config
COPY <<'EOF' /etc/supervisor/conf.d/services.conf
[supervisord]
nodaemon=true
logfile=/dev/stdout
logfile_maxbytes=0

[program:agentgateway]
command=/usr/local/bin/agentgateway -f /etc/agentgateway/config.yaml
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:prometheus]
command=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus --web.listen-address=:9090
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:grafana]
command=/usr/sbin/grafana-server --homepath=/usr/share/grafana --config=/etc/grafana/grafana.ini
directory=/usr/share/grafana
user=grafana
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

EXPOSE 3000 3001 9090 15020

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
DOCKERFILE

# Create or check app
echo -e "${YELLOW}==> Checking Fly.io app...${NC}"
if ! fly apps list 2>/dev/null | grep -q "^$APP_NAME"; then
    echo "Creating app: $APP_NAME"
    fly apps create "$APP_NAME" --machines
fi

# Set secrets
echo -e "${YELLOW}==> Setting secrets...${NC}"
fly secrets set OPENAI_API_KEY="$OPENAI_KEY" -a "$APP_NAME"
if [ -n "$ANTHROPIC_KEY" ]; then
    fly secrets set ANTHROPIC_API_KEY="$ANTHROPIC_KEY" -a "$APP_NAME"
fi
fly secrets set GF_SECURITY_ADMIN_PASSWORD="$(openssl rand -base64 12)" -a "$APP_NAME"

# Deploy
echo -e "${YELLOW}==> Deploying to Fly.io...${NC}"
fly deploy -c fly-observability.toml -a "$APP_NAME"

# Get the generated Grafana password
GRAFANA_PASS=$(fly secrets list -a "$APP_NAME" | grep GF_SECURITY_ADMIN_PASSWORD | awk '{print $2}' 2>/dev/null || echo "Check: fly secrets list -a $APP_NAME")

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Deployment Complete!                       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Endpoints:${NC}"
echo "  LLM Gateway:  https://$APP_NAME.fly.dev"
echo "  Grafana:      https://$APP_NAME.fly.dev:3001"
echo "  Prometheus:   https://$APP_NAME.fly.dev:9090"
echo ""
echo -e "${YELLOW}Grafana Login:${NC}"
echo "  Username: admin"
echo "  Password: (check with: fly secrets list -a $APP_NAME)"
echo ""
echo -e "${YELLOW}Test OpenAI:${NC}"
echo "  curl -X POST https://$APP_NAME.fly.dev/v1/chat/completions \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -H 'Authorization: Bearer \$OPENAI_API_KEY' \\"
echo "    -d '{\"model\": \"gpt-4o-mini\", \"messages\": [{\"role\": \"user\", \"content\": \"Hi\"}]}'"
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo "  fly logs -a $APP_NAME          # View logs"
echo "  fly status -a $APP_NAME        # Check status"
echo "  fly ssh console -a $APP_NAME   # SSH access"
echo ""
