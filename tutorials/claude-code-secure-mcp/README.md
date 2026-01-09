# Claude Code + AgentGateway: Secure MCP with Observability

This tutorial shows how to use **Claude Code** with **AgentGateway** to get:

- ✅ Full observability (metrics, traces, dashboards)
- ✅ Secure MCP server access (JWT authentication)
- ✅ LLM request proxying with token tracking
- ✅ One-click Fly.io deployment

## Architecture

```
┌──────────────┐     ┌─────────────────────────────────────────────┐
│              │     │              AgentGateway                    │
│  Claude Code │────▶│  ┌─────────────────────────────────────────┐│
│              │     │  │  :3000 - Anthropic API (proxied)        ││
└──────────────┘     │  │  • Token tracking                       ││
                     │  │  • Request/response logging             ││
                     │  └─────────────────────────────────────────┘│
                     │  ┌─────────────────────────────────────────┐│
                     │  │  :3001 - MCP Gateway (secured)          ││
                     │  │  • JWT authentication                   ││
                     │  │  • Tool-level authorization             ││
                     │  │  • Audit logging                        ││
                     │  └─────────────────────────────────────────┘│
                     │  ┌─────────────────────────────────────────┐│
                     │  │  :15020 - Metrics                       ││
                     │  │  • Prometheus format                    ││
                     │  └─────────────────────────────────────────┘│
                     └──────────────────┬────────────┬─────────────┘
                                        │            │
                     ┌──────────────────▼──┐    ┌────▼─────────────┐
                     │    Prometheus       │    │     Jaeger       │
                     │    + Grafana        │    │   (Tracing)      │
                     └─────────────────────┘    └──────────────────┘
```

## Quick Start

### Option 1: Local Development

```bash
# 1. Set your API keys
export ANTHROPIC_API_KEY=sk-ant-xxx
export MCP_AUTH_SECRET=your-secret-for-jwt

# 2. Start the stack
cd tutorials/claude-code-secure-mcp
docker-compose up -d

# 3. Configure Claude Code
export ANTHROPIC_BASE_URL=http://localhost:3000
claude
```

### Option 2: Deploy to Fly.io

```bash
./deploy.sh my-claude-gateway
```

---

## Step-by-Step Guide

### Step 1: Understand the Security Model

AgentGateway provides **three layers of security** for MCP:

| Layer | What It Does | Configuration |
|-------|--------------|---------------|
| **Authentication** | Validates JWT tokens | `policies.auth.jwt` |
| **Authorization** | Tool-level access control | `policies.auth.rules` |
| **Audit** | Logs all tool calls | Built-in metrics + traces |

### Step 2: Generate JWT Keys

```bash
# Generate RSA key pair for JWT signing
openssl genrsa -out jwt-private.pem 2048
openssl rsa -in jwt-private.pem -pubout -out jwt-public.pem
```

### Step 3: Configure AgentGateway

See `config.yaml` in this directory for the full configuration. Key sections:

```yaml
# LLM Proxy (no auth required - uses your API key)
binds:
  - port: 3000
    listeners:
      - routes:
          - backends:
              - ai:
                  name: anthropic
                  provider:
                    anthropic: {}

# MCP Gateway (JWT auth required)
  - port: 3001
    listeners:
      - routes:
          - policies:
              auth:
                jwt:
                  issuer: "claude-code-gateway"
                  audience: "mcp-servers"
                  key: "file:./jwt-public.pem"
                rules:
                  # Allow specific tools
                  - 'mcp.tool.name == "read_file"'
                  - 'mcp.tool.name == "list_directory"'
                  # Block dangerous tools
                  - 'mcp.tool.name != "delete_file"'
```

### Step 4: Create MCP Client Token

```bash
# Generate a token for Claude Code to use
./generate-token.sh claude-code-client

# Output: eyJhbGciOiJSUzI1NiIs...
```

### Step 5: Configure Claude Code

Add to your Claude Code config (`~/.claude/settings.json`):

```json
{
  "mcpServers": {
    "secure-filesystem": {
      "url": "http://localhost:3001/mcp/filesystem",
      "headers": {
        "Authorization": "Bearer <your-jwt-token>"
      }
    }
  }
}
```

Or use environment variables:

```bash
export ANTHROPIC_BASE_URL=http://localhost:3000
export MCP_TOKEN=eyJhbGciOiJSUzI1NiIs...
claude
```

### Step 6: Verify Security

```bash
# This should work (authenticated)
curl -X POST http://localhost:3001/mcp/filesystem \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"method": "tools/list"}'

# This should fail (no token)
curl -X POST http://localhost:3001/mcp/filesystem \
  -H "Content-Type: application/json" \
  -d '{"method": "tools/list"}'
# Returns: 401 Unauthorized
```

### Step 7: Monitor in Grafana

1. Open http://localhost:3001 (Grafana)
2. Login: admin / admin
3. Go to "AgentGateway LLM Observability" dashboard
4. See:
   - Token usage from Claude Code
   - MCP tool call metrics
   - Authentication failures
   - Request latencies

---

## Security Policies

### Allow Specific Tools Only

```yaml
policies:
  auth:
    rules:
      # Whitelist approach
      - 'mcp.tool.name in ["read_file", "list_directory", "search"]'
```

### User-Based Access Control

```yaml
policies:
  auth:
    rules:
      # Admin can use all tools
      - 'jwt.role == "admin"'
      # Regular users limited
      - 'jwt.role == "user" && mcp.tool.name != "delete_file"'
```

### Rate Limiting

```yaml
policies:
  rateLimit:
    requestsPerSecond: 10
    burst: 20
```

### IP Allowlist

```yaml
policies:
  auth:
    rules:
      - 'request.ip in ["10.0.0.0/8", "192.168.1.0/24"]'
```

---

## Observability

### Metrics Available

| Metric | Description |
|--------|-------------|
| `agentgateway_gen_ai_client_token_usage` | Claude API token usage |
| `mcp_tool_calls_total` | MCP tool invocations |
| `mcp_auth_failures_total` | Failed authentications |
| `agentgateway_requests_total` | All HTTP requests |

### View Traces

1. Open Jaeger: http://localhost:16686
2. Select service: `agentgateway`
3. See full request flow:
   - Claude Code → AgentGateway
   - AgentGateway → Anthropic API
   - AgentGateway → MCP Server

### Alerts (Grafana)

Pre-configured alerts for:
- High error rate (>5%)
- Authentication failures spike
- Token usage anomalies

---

## Files in This Tutorial

| File | Purpose |
|------|---------|
| `config.yaml` | AgentGateway config with security |
| `docker-compose.yml` | Full local stack |
| `deploy.sh` | Fly.io deployment |
| `generate-token.sh` | JWT token generator |
| `jwt-public.pem` | Example public key |

---

## Fly.io Deployment

### Interactive

```bash
./deploy.sh
```

### With Arguments

```bash
./deploy.sh my-gateway sk-ant-xxx my-jwt-secret
```

### Post-Deployment

```bash
# Set MCP auth secret
fly secrets set MCP_JWT_SECRET=your-secret -a my-gateway

# View logs
fly logs -a my-gateway

# Access Grafana
open https://my-gateway.fly.dev:3002
```

---

## Troubleshooting

### Claude Code Can't Connect

```bash
# Check AgentGateway is running
curl http://localhost:3000/health

# Verify ANTHROPIC_BASE_URL
echo $ANTHROPIC_BASE_URL
```

### MCP Authentication Fails

```bash
# Decode your JWT to check claims
echo $MCP_TOKEN | cut -d. -f2 | base64 -d | jq .

# Verify issuer/audience match config
```

### No Metrics Showing

```bash
# Check metrics endpoint
curl http://localhost:15020/metrics | grep agentgateway
```

---

## Next Steps

1. **Add more MCP servers**: Edit `config.yaml` to add database, API, or custom MCP servers
2. **Custom authorization**: Write CEL expressions for your access patterns
3. **Production hardening**: Enable TLS, set up proper key rotation
4. **Alerting**: Configure PagerDuty/Slack alerts in Grafana
