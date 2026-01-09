#!/usr/bin/env node
/**
 * JWT Token Generator for AgentGateway MCP Authentication
 *
 * Usage:
 *   node generate-token.js
 *
 * Environment variables:
 *   MCP_JWT_SECRET - Secret key for signing (required)
 *   TOKEN_SUBJECT  - User/client identifier (default: claude-code-user)
 *   TOKEN_ROLE     - Role: admin or user (default: user)
 *   TOKEN_EXPIRY   - Expiry time (default: 24h)
 */

const jwt = require('jsonwebtoken');

const secret = process.env.MCP_JWT_SECRET;
if (!secret || secret.length < 32) {
  console.error('Error: MCP_JWT_SECRET must be at least 32 characters');
  console.error('Set it with: export MCP_JWT_SECRET=your-secret-key-min-32-characters!!');
  process.exit(1);
}

const payload = {
  sub: process.env.TOKEN_SUBJECT || 'claude-code-user',
  iss: 'claude-code-gateway',
  aud: 'mcp-servers',
  role: process.env.TOKEN_ROLE || 'user',
  iat: Math.floor(Date.now() / 1000),
  // Custom claims for authorization rules
  permissions: {
    read: true,
    write: process.env.TOKEN_ROLE === 'admin',
    delete: false
  }
};

const options = {
  algorithm: 'HS256',
  expiresIn: process.env.TOKEN_EXPIRY || '24h'
};

const token = jwt.sign(payload, secret, options);

console.log('\n=== MCP Authentication Token ===\n');
console.log('Token:');
console.log(token);
console.log('\n--- Token Details ---');
console.log('Subject:', payload.sub);
console.log('Role:', payload.role);
console.log('Issuer:', payload.iss);
console.log('Audience:', payload.aud);
console.log('Expires:', options.expiresIn);
console.log('\n--- Usage ---');
console.log('\n# Set as environment variable:');
console.log(`export MCP_TOKEN="${token}"`);
console.log('\n# Use with curl:');
console.log(`curl -H "Authorization: Bearer ${token.substring(0, 20)}..." http://localhost:3001/mcp/filesystem`);
console.log('\n# Add to Claude Code config (~/.claude/settings.json):');
console.log(JSON.stringify({
  mcpServers: {
    "secure-filesystem": {
      url: "http://localhost:3001/mcp/filesystem",
      headers: {
        Authorization: `Bearer ${token.substring(0, 50)}...`
      }
    }
  }
}, null, 2));
console.log('\n');
