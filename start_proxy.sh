#!/usr/bin/env bash
# Start the LiteLLM proxy for GitHub Copilot
# Uses native TLS to avoid SSL certificate issues behind corporate proxies

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPILOT_TOKEN_FILE="$HOME/.config/litellm/github_copilot/api-key.json"

AUTH_ONLY=0

usage() {
    echo "Usage: $(basename "$0") [--auth-only]" >&2
    echo "" >&2
    echo "  (no arguments)  Start the LiteLLM proxy and run until interrupted." >&2
    echo "  --auth-only     Perform GitHub Copilot device authentication only," >&2
    echo "                  then exit. Skips launching if already authenticated." >&2
}

for arg in "$@"; do
    case "$arg" in
        --auth-only)
            AUTH_ONLY=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown argument '$arg'" >&2
            usage
            exit 1
            ;;
    esac
done

# Load .env if present into this shell's environment without executing
# arbitrary shell code: read the file line by line and only accept simple
# KEY=VALUE assignments. This also normalizes CRLF line endings (e.g. from
# a .env edited/saved on Windows or WSL) so values don't retain a trailing
# \r, consistent with setup.sh.
if [ -f "$SCRIPT_DIR/.env" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        case "$line" in
            ''|'#'*)
                continue
                ;;
            *=*)
                key="${line%%=*}"
                value="${line#*=}"
                case "$key" in
                    *[!A-Za-z0-9_]*|'')
                        continue
                        ;;
                esac
                export "$key=$value"
                ;;
        esac
    done < "$SCRIPT_DIR/.env"
fi

PORT="${LITELLM_PORT:-4000}"

if ! command -v uv >/dev/null 2>&1; then
    echo "Error: 'uv' is not available in PATH." >&2
    echo "Install it from https://docs.astral.sh/uv/getting-started/installation/" >&2
    exit 1
fi

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

PYTHON_VERSION_OK="$("$PYTHON_BIN" -c '
import sys
major, minor = sys.version_info[0], sys.version_info[1]
print("1" if (major == 3 and 11 <= minor <= 13) else "0")
')"

if [ "$PYTHON_VERSION_OK" != "1" ]; then
    PYTHON_VERSION_STRING="$("$PYTHON_BIN" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
    echo "Error: $PYTHON_BIN is Python $PYTHON_VERSION_STRING; a version between 3.11 and 3.13 is required." >&2
    exit 1
fi

# If we're only authenticating and a token already exists, there's nothing to do.
if [ "$AUTH_ONLY" -eq 1 ] && [ -f "$COPILOT_TOKEN_FILE" ]; then
    echo "GitHub Copilot authentication already present at $COPILOT_TOKEN_FILE"
    exit 0
fi

LITELLM_PID=""

cleanup() {
    if [ -n "$LITELLM_PID" ] && kill -0 "$LITELLM_PID" 2>/dev/null; then
        kill "$LITELLM_PID" 2>/dev/null || true
        wait "$LITELLM_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

if [ "$AUTH_ONLY" -eq 1 ]; then
    echo "Starting LiteLLM proxy for GitHub Copilot authentication …"
    echo ""

    UV_NATIVE_TLS=true PYTHONNOUSERSITE=1 uv run \
        --isolated \
        --no-project \
        --python "$PYTHON_BIN" \
        --with "litellm[proxy]" \
        --with "aiodns>=4.0.4" \
        --with "pycares>=5.0.1" \
        --with "prisma" \
        litellm --config "$SCRIPT_DIR/litellm_config.yaml" --port "$PORT" &
    LITELLM_PID=$!

    echo "Waiting for GitHub Copilot authentication to complete …"
    while [ ! -f "$COPILOT_TOKEN_FILE" ]; do
        if ! kill -0 "$LITELLM_PID" 2>/dev/null; then
            echo "Error: LiteLLM proxy exited before authentication completed." >&2
            LITELLM_PID=""
            exit 1
        fi
        sleep 1
    done

    echo "GitHub Copilot authentication complete."
    cleanup
    LITELLM_PID=""
    trap - EXIT INT TERM
    exit 0
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
    litellm --config "$SCRIPT_DIR/litellm_config.yaml" --port "$PORT" &
LITELLM_PID=$!
wait "$LITELLM_PID"
LITELLM_PID=""
