# Testing LLM Providers with AgentGateway

This guide shows how to test various LLM providers through your AgentGateway deployment.

## Prerequisites

1. Deploy AgentGateway to Fly.io (see README.md)
2. Set your API keys as Fly.io secrets:

```bash
fly secrets set OPENAI_API_KEY=sk-xxx
fly secrets set ANTHROPIC_API_KEY=sk-ant-xxx
```

## Endpoints

| Provider | Endpoint |
|----------|----------|
| OpenAI | `https://your-app.fly.dev/v1/chat/completions` |
| Anthropic | `https://your-app.fly.dev/v1/messages` |
| MCP | `https://your-app.fly.dev:3001/mcp` (via fly proxy) |

---

## Testing OpenAI

### Basic Chat Completion

```bash
curl -X POST https://agentgateway.fly.dev/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [
      {"role": "user", "content": "Say hello in 5 words or less"}
    ]
  }'
```

### Streaming Response

```bash
curl -X POST https://agentgateway.fly.dev/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4o-mini",
    "stream": true,
    "messages": [
      {"role": "user", "content": "Count to 5"}
    ]
  }'
```

### List Models

```bash
curl https://agentgateway.fly.dev/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY"
```

### Using with Python (OpenAI SDK)

```python
from openai import OpenAI

client = OpenAI(
    api_key="your-openai-key",
    base_url="https://agentgateway.fly.dev/v1"
)

response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "Hello!"}]
)
print(response.choices[0].message.content)
```

---

## Testing Anthropic

### Basic Message (Native Format)

```bash
curl -X POST https://agentgateway.fly.dev/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 100,
    "messages": [
      {"role": "user", "content": "Say hello in 5 words or less"}
    ]
  }'
```

### Streaming Response

```bash
curl -X POST https://agentgateway.fly.dev/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 100,
    "stream": true,
    "messages": [
      {"role": "user", "content": "Count to 5"}
    ]
  }'
```

### Using with Python (Anthropic SDK)

```python
import anthropic

client = anthropic.Anthropic(
    api_key="your-anthropic-key",
    base_url="https://agentgateway.fly.dev"
)

message = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=100,
    messages=[{"role": "user", "content": "Hello!"}]
)
print(message.content[0].text)
```

### Using with Claude Code

Point Claude Code at your gateway:

```bash
export ANTHROPIC_API_KEY="sk-ant-xxx"
export ANTHROPIC_BASE_URL="https://agentgateway.fly.dev"
claude
```

---

## Testing MCP (Model Context Protocol)

MCP runs on port 3001. To access it through Fly.io:

### Option 1: Fly Proxy (Recommended for testing)

```bash
# In one terminal, start the proxy
fly proxy 3001:3001 -a agentgateway

# In another terminal, test MCP
curl http://localhost:3001/mcp/sse
```

### Option 2: Direct via SSH

```bash
fly ssh console -a agentgateway
curl http://localhost:3001/mcp
```

---

## Local Testing

Before deploying, test locally:

```bash
# Install AgentGateway
curl https://raw.githubusercontent.com/agentgateway/agentgateway/refs/heads/main/common/scripts/get-agentgateway | bash

# Run with config
agentgateway -f config.yaml

# Test in another terminal
curl -X POST http://localhost:3000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{"model": "gpt-4o-mini", "messages": [{"role": "user", "content": "Hi"}]}'
```

---

## Troubleshooting

### Check Logs

```bash
fly logs -a agentgateway
```

### Verify Secrets

```bash
fly secrets list -a agentgateway
```

### SSH into Container

```bash
fly ssh console -a agentgateway
```

### Common Issues

| Issue | Solution |
|-------|----------|
| 401 Unauthorized | Check API key is set: `fly secrets list` |
| Connection refused | Verify app is running: `fly status` |
| Timeout | Check region latency, consider changing `primary_region` |
| CORS errors | Verify `allowOrigins` in config.yaml |

---

## Health Check

Simple health check to verify the gateway is running:

```bash
curl -I https://agentgateway.fly.dev/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY"
```

Expected: `HTTP/2 200`
