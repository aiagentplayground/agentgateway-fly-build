#!/bin/bash
# Generate JWT token for MCP authentication
#
# Usage:
#   ./generate-token.sh                    # Interactive
#   ./generate-token.sh user my-secret     # With args
#   ./generate-token.sh admin my-secret    # Admin role

set -e

ROLE="${1:-user}"
SECRET="${2:-$MCP_JWT_SECRET}"

if [ -z "$SECRET" ] || [ ${#SECRET} -lt 32 ]; then
    echo "Error: MCP_JWT_SECRET must be at least 32 characters"
    echo ""
    echo "Usage:"
    echo "  export MCP_JWT_SECRET='your-secret-key-min-32-characters!!'"
    echo "  ./generate-token.sh [role]"
    echo ""
    echo "Or:"
    echo "  ./generate-token.sh user 'your-secret-key-min-32-characters!!'"
    exit 1
fi

# Check if node is available
if command -v node &> /dev/null; then
    # Use Node.js version
    MCP_JWT_SECRET="$SECRET" TOKEN_ROLE="$ROLE" node generate-token.js
else
    # Fallback: Use Docker
    echo "Node.js not found, using Docker..."
    docker run --rm \
        -e MCP_JWT_SECRET="$SECRET" \
        -e TOKEN_ROLE="$ROLE" \
        -v "$(pwd)/generate-token.js:/app/generate-token.js:ro" \
        -w /app \
        node:20-slim \
        bash -c "npm install jsonwebtoken 2>/dev/null && node generate-token.js"
fi
