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

if [ -z "${PYTHON_BIN:-}" ]; then
    if command -v python >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python)"
    elif command -v python3 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3)"
    else
        echo "Error: neither 'python' nor 'python3' is available in PATH." >&2
        exit 1
    fi
fi

echo "Starting LiteLLM proxy on port $PORT …"
echo ""
echo "Configure Claude Code:"
echo "  export ANTHROPIC_BASE_URL=http://localhost:$PORT"
echo "  export ANTHROPIC_AUTH_TOKEN=\$LITELLM_MASTER_KEY"
echo "  claude"
echo ""

UV_NATIVE_TLS=true PYTHONNOUSERSITE=1 uv run \
    --isolated \
    --no-project \
    --python "$PYTHON_BIN" \
    --with "litellm[proxy]" \
    --with "aiodns>=4.0.4" \
    --with "pycares>=5.0.1" \
    --with "prisma" \
    litellm --config "$SCRIPT_DIR/litellm_config.yaml" --port "$PORT"
