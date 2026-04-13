#!/usr/bin/env bash
# Start the LiteLLM proxy for Azure AI Foundry
# Uses native TLS to avoid SSL certificate issues behind corporate proxies

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env if present
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

PORT="${LITELLM_PORT:-4000}"

echo "Starting LiteLLM proxy on port $PORT …"
echo ""
echo "Configure Claude Code:"
echo "  export ANTHROPIC_BASE_URL=http://localhost:$PORT"
echo "  export ANTHROPIC_AUTH_TOKEN=\$LITELLM_MASTER_KEY"
echo "  claude"
echo ""

UV_NATIVE_TLS=true uv run \
    --with "litellm[proxy]" \
    litellm --config "$SCRIPT_DIR/litellm_config.yaml" --port "$PORT"
