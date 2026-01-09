#!/bin/bash
# Deploy AgentGateway to Fly.io
#
# Prerequisites:
#   - Install flyctl: curl -L https://fly.io/install.sh | sh
#   - Login: fly auth login
#
# Usage:
#   ./deploy.sh              # Deploy with default app name
#   ./deploy.sh my-gateway   # Deploy with custom app name

set -e

APP_NAME="${1:-agentgateway}"

echo "==> Deploying AgentGateway to Fly.io..."
echo "    App name: $APP_NAME"

# Check if flyctl is installed
if ! command -v fly &> /dev/null; then
    echo "Error: flyctl not installed. Install with:"
    echo "  curl -L https://fly.io/install.sh | sh"
    exit 1
fi

# Check if logged in
if ! fly auth whoami &> /dev/null; then
    echo "Error: Not logged in to Fly.io. Run: fly auth login"
    exit 1
fi

# Update app name in fly.toml if custom name provided
if [ "$APP_NAME" != "agentgateway" ]; then
    sed -i "s/^app = .*/app = \"$APP_NAME\"/" fly.toml
fi

# Check if app exists, if not create it
if ! fly apps list | grep -q "^$APP_NAME"; then
    echo "==> Creating new Fly.io app: $APP_NAME"
    fly apps create "$APP_NAME"
fi

# Deploy
echo "==> Deploying..."
fly deploy

echo ""
echo "==> Deployment complete!"
echo "    URL: https://$APP_NAME.fly.dev"
echo ""
echo "View logs with: fly logs -a $APP_NAME"
