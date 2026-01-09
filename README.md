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

## Files

| File | Description |
|------|-------------|
| `Dockerfile` | Container image that installs AgentGateway |
| `fly.toml` | Fly.io deployment configuration |
| `config.yaml` | AgentGateway configuration |
| `deploy.sh` | Deployment helper script |

## Customization

### App Name

Deploy with a custom app name:

```bash
./deploy.sh my-custom-gateway
```

### Configuration

Edit `config.yaml` to customize AgentGateway behavior. See the [AgentGateway docs](https://github.com/agentgateway/agentgateway) for configuration options.

### Resources

Adjust VM resources in `fly.toml`:

```toml
[[vm]]
  memory = "1gb"    # Increase memory
  cpu_kind = "shared"
  cpus = 2          # More CPUs
```

## Manual Deployment

If you prefer not to use the script:

```bash
fly apps create agentgateway
fly deploy
```

## Useful Commands

```bash
fly logs -a agentgateway     # View logs
fly status -a agentgateway   # Check status
fly ssh console              # SSH into container
fly destroy agentgateway     # Delete app
```
