# AgentGateway Fly.io Deployment

Deploy [AgentGateway](https://github.com/agentgateway/agentgateway) to Fly.io with one command.

## Quick Start

```bash
# Install Fly CLI (if needed)
curl -L https://fly.io/install.sh | sh

# Login to Fly.io
fly auth login

# Deploy
./deploy.sh
```

## Networking

Fly.io handles TLS termination at the edge:

| External | Internal | Purpose |
|----------|----------|---------|
| `https://your-app.fly.dev` (443) | Port 3000 | LLM Gateway (OpenAI/Anthropic) |
| `http://your-app.fly.dev` (80) | Redirects to HTTPS | - |
| `fly proxy 3001:3001` | Port 3001 | MCP Server Gateway |

**Note:** You access everything via HTTPS. Fly.io automatically handles the TLS certificates.

## Set API Keys

```bash
fly secrets set OPENAI_API_KEY=sk-xxx
fly secrets set ANTHROPIC_API_KEY=sk-ant-xxx
```

## Test Your Deployment

```bash
# Test OpenAI
curl -X POST https://agentgateway.fly.dev/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{"model": "gpt-4o-mini", "messages": [{"role": "user", "content": "Hi"}]}'

# Test Anthropic
curl -X POST https://agentgateway.fly.dev/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model": "claude-sonnet-4-20250514", "max_tokens": 100, "messages": [{"role": "user", "content": "Hi"}]}'
```

See [TESTING.md](TESTING.md) for comprehensive testing guide with Python examples.

## Files

| File | Description |
|------|-------------|
| `Dockerfile` | Container image that installs AgentGateway |
| `fly.toml` | Fly.io deployment configuration |
| `config.yaml` | AgentGateway config (OpenAI, Anthropic, MCP) |
| `deploy.sh` | Deployment helper script |
| `TESTING.md` | LLM provider testing guide |

## Customization

### App Name

```bash
./deploy.sh my-custom-gateway
```

### Configuration

Edit `config.yaml` to customize:
- LLM providers (OpenAI, Anthropic, etc.)
- MCP server backends
- CORS policies
- Rate limiting

See [AgentGateway docs](https://agentgateway.dev/docs/) for all options.

### Resources

Adjust VM resources in `fly.toml`:

```toml
[[vm]]
  memory = "1gb"
  cpu_kind = "shared"
  cpus = 2
```

## Use with Claude Code

Point Claude Code at your gateway:

```bash
export ANTHROPIC_API_KEY="sk-ant-xxx"
export ANTHROPIC_BASE_URL="https://agentgateway.fly.dev"
claude
```

## Useful Commands

```bash
fly logs -a agentgateway        # View logs
fly status -a agentgateway      # Check status
fly secrets list                # List secrets
fly ssh console                 # SSH into container
fly proxy 3001:3001             # Access MCP port locally
fly destroy agentgateway        # Delete app
```
