#!/bin/bash
# Deploy Claude Code Gateway to Fly.io
#
# Includes:
#   - AgentGateway (LLM proxy + secure MCP)
#   - Prometheus (metrics)
#   - Grafana (dashboards)
#
# Usage:
#   ./deploy.sh                              # Interactive
#   ./deploy.sh my-gateway                   # With app name
#   ./deploy.sh my-gateway sk-ant-xxx secret # Full args

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║   Claude Code + AgentGateway                                      ║
║   Secure MCP with Full Observability                              ║
║                                                                   ║
║   Deploy to Fly.io                                                ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check prerequisites
if ! command -v fly &> /dev/null; then
    echo -e "${RED}Error: flyctl not installed${NC}"
    echo "Install: curl -L https://fly.io/install.sh | sh"
    exit 1
fi

if ! fly auth whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged in to Fly.io${NC}"
    echo "Run: fly auth login"
    exit 1
fi

# Get configuration
APP_NAME="${1:-}"
if [ -z "$APP_NAME" ]; then
    read -p "App name (default: claude-gateway): " APP_NAME
    APP_NAME="${APP_NAME:-claude-gateway}"
fi

ANTHROPIC_KEY="${2:-}"
if [ -z "$ANTHROPIC_KEY" ]; then
    read -sp "Anthropic API key: " ANTHROPIC_KEY
    echo
fi

if [ -z "$ANTHROPIC_KEY" ]; then
    echo -e "${RED}Error: Anthropic API key required${NC}"
    exit 1
fi

JWT_SECRET="${3:-}"
if [ -z "$JWT_SECRET" ]; then
    # Generate a random secret
    JWT_SECRET=$(openssl rand -base64 32 | tr -d '\n')
    echo -e "${YELLOW}Generated JWT secret (save this!):${NC}"
    echo "$JWT_SECRET"
    echo ""
fi

echo -e "${YELLOW}Configuration:${NC}"
echo "  App name: $APP_NAME"
echo "  Region: iad (US East)"
echo ""

# Create fly.toml
cat > fly.toml << EOF
app = "$APP_NAME"
primary_region = "iad"

[build]
  dockerfile = "Dockerfile"

[http_service]
  internal_port = 3000
  force_https = true
  auto_stop_machines = "suspend"
  auto_start_machines = true
  min_machines_running = 1

  [http_service.concurrency]
    type = "connections"
    hard_limit = 100
    soft_limit = 80

# MCP Gateway (secured)
[[services]]
  internal_port = 3001
  protocol = "tcp"
  [[services.ports]]
    handlers = ["tls", "http"]
    port = 3001

# Grafana
[[services]]
  internal_port = 3002
  protocol = "tcp"
  [[services.ports]]
    handlers = ["tls", "http"]
    port = 3002

# Prometheus
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
  GF_SERVER_HTTP_PORT = "3002"
EOF

# Create Dockerfile
cat > Dockerfile << 'DOCKERFILE'
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    curl wget supervisor ca-certificates \
    nodejs npm adduser libfontconfig1 musl \
    && rm -rf /var/lib/apt/lists/*

# Install AgentGateway
RUN curl -sL https://raw.githubusercontent.com/agentgateway/agentgateway/refs/heads/main/common/scripts/get-agentgateway | bash \
    && mv /root/.agentgateway/bin/agentgateway /usr/local/bin/

# Install Prometheus
RUN wget -q https://github.com/prometheus/prometheus/releases/download/v2.48.0/prometheus-2.48.0.linux-amd64.tar.gz \
    && tar xzf prometheus-2.48.0.linux-amd64.tar.gz \
    && mv prometheus-2.48.0.linux-amd64/prometheus /usr/local/bin/ \
    && rm -rf prometheus-*

# Install Grafana
RUN wget -q https://dl.grafana.com/oss/release/grafana_10.2.2_amd64.deb \
    && dpkg -i grafana_10.2.2_amd64.deb \
    && rm grafana_10.2.2_amd64.deb

# Create directories
RUN mkdir -p /etc/agentgateway /etc/prometheus /var/lib/prometheus /workspace

# Copy configs
COPY config.yaml /etc/agentgateway/config.yaml
COPY prometheus.yml /etc/prometheus/prometheus.yml
COPY grafana/provisioning /etc/grafana/provisioning

# Fix Prometheus config for localhost
RUN sed -i 's/agentgateway:15020/localhost:15020/g' /etc/prometheus/prometheus.yml

# Supervisor config
RUN cat > /etc/supervisor/conf.d/services.conf << 'EOF'
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

[program:grafana]
command=/usr/sbin/grafana-server --homepath=/usr/share/grafana --config=/etc/grafana/grafana.ini
directory=/usr/share/grafana
user=grafana
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
EOF

EXPOSE 3000 3001 3002 9090 15020

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
DOCKERFILE

# Create/check app
echo -e "${YELLOW}==> Setting up Fly.io app...${NC}"
if ! fly apps list 2>/dev/null | grep -q "^$APP_NAME"; then
    fly apps create "$APP_NAME" --machines
fi

# Set secrets
echo -e "${YELLOW}==> Configuring secrets...${NC}"
GRAFANA_PASS=$(openssl rand -base64 12)
fly secrets set \
    ANTHROPIC_API_KEY="$ANTHROPIC_KEY" \
    MCP_JWT_SECRET="$JWT_SECRET" \
    GF_SECURITY_ADMIN_PASSWORD="$GRAFANA_PASS" \
    -a "$APP_NAME"

# Deploy
echo -e "${YELLOW}==> Deploying to Fly.io...${NC}"
fly deploy -a "$APP_NAME"

# Generate a token for the user
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Deployment Complete!                            ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Endpoints:${NC}"
echo "  LLM Gateway:  https://$APP_NAME.fly.dev"
echo "  MCP Gateway:  https://$APP_NAME.fly.dev:3001"
echo "  Grafana:      https://$APP_NAME.fly.dev:3002"
echo "  Prometheus:   https://$APP_NAME.fly.dev:9090"
echo ""
echo -e "${YELLOW}Grafana Login:${NC}"
echo "  Username: admin"
echo "  Password: $GRAFANA_PASS"
echo ""
echo -e "${YELLOW}Configure Claude Code:${NC}"
echo "  export ANTHROPIC_BASE_URL=https://$APP_NAME.fly.dev"
echo "  export ANTHROPIC_API_KEY=your-key"
echo "  claude"
echo ""
echo -e "${YELLOW}Generate MCP Token:${NC}"
echo "  export MCP_JWT_SECRET='$JWT_SECRET'"
echo "  ./generate-token.sh user"
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo "  fly logs -a $APP_NAME"
echo "  fly ssh console -a $APP_NAME"
echo ""
