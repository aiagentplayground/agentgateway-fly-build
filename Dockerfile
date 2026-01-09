# Dockerfile for AgentGateway on Fly.io
FROM debian:bookworm-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Install AgentGateway
RUN curl -sL https://raw.githubusercontent.com/agentgateway/agentgateway/refs/heads/main/common/scripts/get-agentgateway | bash

# Create app directory
WORKDIR /app

# Copy config file
COPY config.yaml /app/config.yaml

# Expose the default port
EXPOSE 3000

# Run AgentGateway
CMD ["agentgateway", "-f", "/app/config.yaml"]
