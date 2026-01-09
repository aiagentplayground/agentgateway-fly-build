# AgentGateway Observability Tutorial

Deploy AgentGateway with full observability: **Prometheus metrics**, **Grafana dashboards**, and **Jaeger tracing**.

## What You'll Get

| Component | Purpose | Port |
|-----------|---------|------|
| AgentGateway | LLM proxy (OpenAI, Anthropic) | 3000 |
| Prometheus | Metrics collection | 9090 |
| Grafana | Dashboards & visualization | 3001 |
| Jaeger | Distributed tracing | 16686 |
| OTel Collector | Trace pipeline | 4317 |

## Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│   Client    │────▶│   AgentGateway   │────▶│   OpenAI    │
│  (curl/SDK) │     │   :3000          │     │  Anthropic  │
└─────────────┘     └────────┬─────────┘     └─────────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
        ┌──────────┐  ┌────────────┐  ┌──────────┐
        │Prometheus│  │OTel Collect│  │  Stdout  │
        │  :9090   │  │   :4317    │  │   Logs   │
        └────┬─────┘  └─────┬──────┘  └──────────┘
             │              │
             ▼              ▼
        ┌──────────┐  ┌──────────┐
        │ Grafana  │  │  Jaeger  │
        │  :3001   │  │  :16686  │
        └──────────┘  └──────────┘
```

## Quick Start (Local Docker)

### 1. Clone and Setup

```bash
cd observability
```

### 2. Set Your API Key

```bash
export OPENAI_API_KEY=sk-xxx
# Optional:
export ANTHROPIC_API_KEY=sk-ant-xxx
```

### 3. Start the Stack

```bash
docker-compose up -d
```

### 4. Access Dashboards

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3001 | admin / admin |
| Prometheus | http://localhost:9090 | - |
| Jaeger | http://localhost:16686 | - |
| AgentGateway | http://localhost:3000 | - |

### 5. Test It

```bash
# Make a request through AgentGateway
curl -X POST http://localhost:3000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### 6. View Metrics

```bash
# Raw Prometheus metrics
curl http://localhost:15020/metrics

# Check Grafana dashboard
open http://localhost:3001
```

---

## Deploy to Fly.io

### Interactive Deploy

```bash
./deploy-fly.sh
```

You'll be prompted for:
- App name (default: agentgateway)
- OpenAI API key
- Anthropic API key (optional)

### Non-Interactive Deploy

```bash
./deploy-fly.sh my-gateway sk-xxx-your-key
```

### Access Your Stack

After deployment:
- **LLM Gateway**: `https://my-gateway.fly.dev`
- **Grafana**: `https://my-gateway.fly.dev:3001`
- **Prometheus**: `https://my-gateway.fly.dev:9090`

---

## Available Metrics

AgentGateway exposes these Prometheus metrics at `:15020/metrics`:

### LLM Metrics

| Metric | Description | Labels |
|--------|-------------|--------|
| `agentgateway_gen_ai_client_token_usage` | Token usage histogram | token_type, model, provider |
| `agentgateway_requests_total` | Total HTTP requests | status, method, backend |

### MCP Metrics

| Metric | Description |
|--------|-------------|
| `tool_calls_total` | Total tool invocations |
| `tool_call_errors_total` | Failed tool calls |
| `list_calls_total` | Resource listing ops |
| `read_resource_calls_total` | Resource reads |
| `get_prompt_calls_total` | Prompt retrievals |

### Example Queries (PromQL)

```promql
# Request rate per second
sum(rate(agentgateway_requests_total[5m]))

# Token usage by model
sum by (gen_ai_response_model) (rate(agentgateway_gen_ai_client_token_usage_sum[5m]))

# Error rate
sum(rate(agentgateway_requests_total{status=~"5.."}[5m]))
  / sum(rate(agentgateway_requests_total[5m]))

# Tokens per request
sum(rate(agentgateway_gen_ai_client_token_usage_sum[5m]))
  / sum(rate(agentgateway_requests_total[5m]))
```

---

## Tracing

AgentGateway sends traces via OpenTelemetry. View them in Jaeger:

1. Open http://localhost:16686 (or your Fly.io Jaeger URL)
2. Select "agentgateway" from the Service dropdown
3. Click "Find Traces"

### Trace Data Includes

- Request path through the gateway
- Backend provider calls (OpenAI, Anthropic)
- Latency breakdown
- Error details

### Configuration

Tracing is enabled in `agentgateway-config.yaml`:

```yaml
config:
  tracing:
    otlpEndpoint: http://otel-collector:4317
    randomSampling: true
```

---

## Grafana Dashboard

The pre-configured dashboard includes:

### Overview Row
- Request rate (req/s)
- Total requests (1h)
- Error rate
- Tokens used (1h)

### Token Usage Row
- Input vs Output tokens over time
- Token usage by model

### Requests Row
- Requests by status code (2xx, 4xx, 5xx)
- Requests by backend (OpenAI, Anthropic)

### Tool Calls Row (MCP)
- Tool call rate
- MCP operation breakdown

---

## Configuration Reference

### AgentGateway Config

```yaml
config:
  tracing:
    otlpEndpoint: http://otel-collector:4317
    randomSampling: true

binds:
  - port: 3000
    listeners:
      - routes:
          - backends:
              - ai:
                  name: openai
                  provider:
                    openAI: {}
                  routes:
                    /v1/chat/completions: completions
```

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `OPENAI_API_KEY` | OpenAI API key | Yes |
| `ANTHROPIC_API_KEY` | Anthropic API key | No |
| `GF_SECURITY_ADMIN_PASSWORD` | Grafana admin password | Auto-generated |

---

## Troubleshooting

### No Metrics Showing

```bash
# Check AgentGateway is exposing metrics
curl http://localhost:15020/metrics

# Check Prometheus targets
open http://localhost:9090/targets
```

### No Traces in Jaeger

```bash
# Check OTel collector logs
docker-compose logs otel-collector

# Verify tracing config in agentgateway-config.yaml
```

### Container Issues

```bash
# View all logs
docker-compose logs -f

# Restart specific service
docker-compose restart agentgateway

# Full reset
docker-compose down -v && docker-compose up -d
```

### Fly.io Issues

```bash
# View logs
fly logs -a my-gateway

# SSH into container
fly ssh console -a my-gateway

# Check secrets
fly secrets list -a my-gateway
```

---

## Files

| File | Description |
|------|-------------|
| `docker-compose.yml` | Full local stack definition |
| `agentgateway-config.yaml` | AgentGateway with tracing enabled |
| `otel-collector-config.yaml` | OpenTelemetry pipeline |
| `prometheus/prometheus.yml` | Prometheus scrape config |
| `grafana/provisioning/` | Datasources & dashboards |
| `deploy-fly.sh` | Fly.io deployment script |
