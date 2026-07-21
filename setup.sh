#!/usr/bin/env bash
# One-command setup: verify prerequisites, create .env, authenticate with
# GitHub Copilot, and configure Claude Code to use the local proxy.
#
# Written for Bash 3.2 (macOS default) as well as Linux and WSL2: no
# associative arrays, no `readlink -f`/`realpath`, no `sed -i`, no other
# GNU-only or Bash-4+ constructs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
ENV_EXAMPLE_FILE="$SCRIPT_DIR/.env.example"
LITELLM_CONFIG_FILE="$SCRIPT_DIR/litellm_config.yaml"
START_PROXY_SCRIPT="$SCRIPT_DIR/start_proxy.sh"
COPILOT_TOKEN_FILE="$HOME/.config/litellm/github_copilot/api-key.json"
CLAUDE_SETTINGS_DIR="$HOME/.claude"
CLAUDE_SETTINGS_FILE="$CLAUDE_SETTINGS_DIR/settings.json"

# ------------------------------------------------------------------------
# Restrained terminal UI
#
# Colors only when stdout is an interactive terminal and the environment
# does not opt out (NO_COLOR, TERM=dumb). No spinners, no cursor
# repositioning, no external UI dependency: this must stay robust on
# macOS Bash 3.2, Linux, WSL2, CI logs, and screen readers.
# ------------------------------------------------------------------------

USE_COLOR=0
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
    USE_COLOR=1
fi

if [ "$USE_COLOR" -eq 1 ]; then
    BOLD="$(printf '\033[1m')"
    DIM="$(printf '\033[2m')"
    RED="$(printf '\033[31m')"
    GREEN="$(printf '\033[32m')"
    YELLOW="$(printf '\033[33m')"
    RESET="$(printf '\033[0m')"
else
    BOLD=""
    DIM=""
    RED=""
    GREEN=""
    YELLOW=""
    RESET=""
fi

heading() {
    printf '%s\n' "${BOLD}LiteLLM Claude Code Proxy — Setup${RESET}"
}

step() {
    # $1: step label
    printf '\n%s\n' "${BOLD}==> $1${RESET}"
}

info() {
    # $1: primary message
    printf '%s\n' "  $1"
}

detail() {
    # $1: secondary/explanatory message, printed dim
    printf '%s\n' "  ${DIM}$1${RESET}"
}

ok() {
    printf '%s\n' "  ${GREEN}[ok]${RESET} $1"
}

warn() {
    printf '%s\n' "  ${YELLOW}[warn]${RESET} $1"
}

fail_line() {
    printf '%s\n' "  ${RED}[fail]${RESET} $1" >&2
}

# ------------------------------------------------------------------------
# 1. Prerequisite checks — aggregate every problem into one actionable
#    failure instead of stopping at the first missing tool.
# ------------------------------------------------------------------------

heading
step "Checking prerequisites"

PREREQ_ERRORS=""

add_error() {
    # $1: message to append to the aggregated error list
    if [ -z "$PREREQ_ERRORS" ]; then
        PREREQ_ERRORS="$1"
    else
        PREREQ_ERRORS="$PREREQ_ERRORS
$1"
    fi
}

# uv
if command -v uv >/dev/null 2>&1; then
    ok "uv found ($(command -v uv))"
else
    fail_line "uv not found"
    add_error "Install uv: https://docs.astral.sh/uv/getting-started/installation/"
fi

# Python, honoring PYTHON_BIN
PYTHON_BIN="${PYTHON_BIN:-}"
if [ -n "$PYTHON_BIN" ]; then
    if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
        fail_line "PYTHON_BIN='$PYTHON_BIN' is not executable"
        add_error "Set PYTHON_BIN to a working Python 3.11-3.13 interpreter, or unset it to allow auto-detection."
        PYTHON_BIN=""
    fi
elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python)"
elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3)"
else
    fail_line "neither 'python' nor 'python3' found in PATH"
    add_error "Install Python 3.11-3.13 and ensure it is in PATH, or set PYTHON_BIN."
fi

if [ -n "$PYTHON_BIN" ]; then
    PYTHON_VERSION_OK="$("$PYTHON_BIN" -c '
import sys
major, minor = sys.version_info[0], sys.version_info[1]
print("1" if (major == 3 and 11 <= minor <= 13) else "0")
' 2>/dev/null || echo "0")"

    PYTHON_VERSION_STRING="$("$PYTHON_BIN" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo "unknown")"

    if [ "$PYTHON_VERSION_OK" = "1" ]; then
        ok "Python $PYTHON_VERSION_STRING found ($PYTHON_BIN)"
    else
        fail_line "$PYTHON_BIN is Python $PYTHON_VERSION_STRING"
        add_error "Python 3.11-3.13 is required (found $PYTHON_VERSION_STRING at $PYTHON_BIN). Set PYTHON_BIN to override."
    fi
fi

# Docker
if command -v docker >/dev/null 2>&1; then
    ok "docker found ($(command -v docker))"
else
    fail_line "docker not found"
    add_error "Install Docker: https://docs.docker.com/get-docker/"
fi

# docker compose plugin
if command -v docker >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1; then
        ok "docker compose plugin available"
    else
        fail_line "'docker compose' is not working"
        add_error "Install/enable the Docker Compose plugin: https://docs.docker.com/compose/install/"
    fi
fi

# claude
if command -v claude >/dev/null 2>&1; then
    ok "claude found ($(command -v claude))"
else
    fail_line "claude not found"
    add_error "Install Claude Code: https://docs.claude.com/en/docs/claude-code/setup"
fi

if [ -n "$PREREQ_ERRORS" ]; then
    printf '\n%s\n' "${BOLD}${RED}Setup cannot continue — missing or invalid prerequisites:${RESET}"
    printf '%s\n' "$PREREQ_ERRORS" | while IFS= read -r line; do
        printf '  - %s\n' "$line"
    done
    printf '\n%s\n' "Note: a GitHub Copilot subscription (personal or enterprise) is also required for authentication, but this cannot be checked locally."
    exit 1
fi

detail "A GitHub Copilot subscription (personal or enterprise) is required for authentication; this cannot be checked locally."

# ------------------------------------------------------------------------
# 2. Create .env from the template, never overwriting an existing file.
# ------------------------------------------------------------------------

step "Configuring .env"

if [ -f "$ENV_FILE" ]; then
    ok ".env already exists — leaving it untouched"
else
    if [ ! -f "$ENV_EXAMPLE_FILE" ]; then
        fail_line ".env.example not found at $ENV_EXAMPLE_FILE"
        exit 1
    fi
    cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"
    ok "Created .env from .env.example"
    detail "Edit .env now if you want to change the port, master key, or credentials."
fi

# Load .env into this shell's environment without letting an unset
# variable trip `set -u`, and without executing arbitrary shell code:
# read the file line by line and only accept simple KEY=VALUE assignments.
if [ ! -f "$ENV_FILE" ]; then
    fail_line ".env is missing after setup; cannot continue"
    exit 1
fi

while IFS= read -r line || [ -n "$line" ]; do
    # Strip a single trailing CR so .env files edited/saved on Windows or
    # WSL with CRLF line endings parse the same as LF-only files.
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
done < "$ENV_FILE"

if [ -z "${LITELLM_PORT:-}" ]; then
    fail_line "LITELLM_PORT is not set in .env"
    exit 1
fi

case "$LITELLM_PORT" in
    ''|*[!0-9]*)
        fail_line "LITELLM_PORT='$LITELLM_PORT' is not a valid port number"
        exit 1
        ;;
esac
if [ "$LITELLM_PORT" -lt 1 ] || [ "$LITELLM_PORT" -gt 65535 ]; then
    fail_line "LITELLM_PORT='$LITELLM_PORT' is out of range (1-65535)"
    exit 1
fi

if [ -z "${LITELLM_MASTER_KEY:-}" ]; then
    fail_line "LITELLM_MASTER_KEY is not set in .env"
    exit 1
fi

ok "LITELLM_PORT=$LITELLM_PORT"
ok "LITELLM_MASTER_KEY is set"

# ------------------------------------------------------------------------
# 3. GitHub Copilot authentication (idempotent).
# ------------------------------------------------------------------------

step "GitHub Copilot authentication"

if [ -f "$COPILOT_TOKEN_FILE" ]; then
    ok "Authentication already present at $COPILOT_TOKEN_FILE"
else
    info "No GitHub Copilot token found."
    detail "This uses GitHub's OAuth device flow: the proxy will print a URL and a"
    detail "one-time code. Open the URL, enter the code, and approve access."
    detail "The token is then stored locally and refreshes on its own."
    printf '\n'
    if [ ! -x "$START_PROXY_SCRIPT" ]; then
        fail_line "$START_PROXY_SCRIPT is missing or not executable"
        exit 1
    fi
    "$START_PROXY_SCRIPT" --auth-only
    if [ ! -f "$COPILOT_TOKEN_FILE" ]; then
        fail_line "Authentication did not complete (token not found at $COPILOT_TOKEN_FILE)"
        exit 1
    fi
    ok "GitHub Copilot authentication complete"
fi

# ------------------------------------------------------------------------
# 4. Merge required settings into ~/.claude/settings.json.
# ------------------------------------------------------------------------

step "Configuring Claude Code"

ANTHROPIC_BASE_URL="http://localhost:$LITELLM_PORT"

info "The following will be added/changed in $CLAUDE_SETTINGS_FILE:"
printf '\n'
printf '  %s\n' "env.ANTHROPIC_BASE_URL   = $ANTHROPIC_BASE_URL"
printf '  %s\n' "env.ANTHROPIC_AUTH_TOKEN = <LITELLM_MASTER_KEY> (hidden)"
printf '  %s\n' "alwaysThinkingEnabled    = false"
printf '\n'
detail "Claude Code needs the base URL and token to reach the local proxy instead"
detail "of Anthropic's API. Without these settings, the proxy workflow will not work."
printf '\n'
detail "alwaysThinkingEnabled is deliberately disabled because GPT models exposed"
detail "through GitHub Copilot do not support Claude Code's extended-thinking"
detail "protocol. Leaving it enabled can make GPT-backed model requests fail or"
detail "behave incompatibly. This does NOT disable normal model reasoning/effort"
detail "controls (e.g. /effort or effortLevel) — only the extended-thinking toggle."
printf '\n'
if [ -f "$CLAUDE_SETTINGS_FILE" ]; then
    warn "Any existing values for these same keys will be overwritten."
fi

printf '%s' "  Apply these settings? [y/N] "
REPLY=""
read -r REPLY || true
case "$REPLY" in
    [yY]|[yY][eE][sS])
        ;;
    *)
        SKIP_CLAUDE_CONFIG=1
        warn "Claude Code settings were not altered."
        detail "The proxy workflow will not work unless these settings are already configured."
        ;;
esac

if [ "${SKIP_CLAUDE_CONFIG:-0}" != "1" ]; then
    mkdir -p "$CLAUDE_SETTINGS_DIR"

MERGE_STATUS_FILE="$(mktemp 2>/dev/null || echo "/tmp/setup_sh_merge_status.$$")"
rm -f "$MERGE_STATUS_FILE"

MERGE_EXIT=0
ANTHROPIC_BASE_URL="$ANTHROPIC_BASE_URL" \
LITELLM_MASTER_KEY="$LITELLM_MASTER_KEY" \
CLAUDE_SETTINGS_FILE="$CLAUDE_SETTINGS_FILE" \
MERGE_STATUS_FILE="$MERGE_STATUS_FILE" \
"$PYTHON_BIN" <<'PYEOF' || MERGE_EXIT=$?
import json
import os
import stat
import sys
import tempfile

settings_path = os.environ["CLAUDE_SETTINGS_FILE"]
status_path = os.environ["MERGE_STATUS_FILE"]
base_url = os.environ["ANTHROPIC_BASE_URL"]
master_key = os.environ["LITELLM_MASTER_KEY"]

def fail(message):
    with open(status_path, "w") as status_file:
        status_file.write("error: " + message + "\n")
    sys.exit(1)

data = {}
existing_mode = None
if os.path.exists(settings_path):
    try:
        with open(settings_path, "r") as f:
            raw = f.read()
    except OSError as exc:
        fail("cannot read {}: {}".format(settings_path, exc))

    if raw.strip():
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            fail(
                "{} contains malformed JSON ({}); left unchanged".format(
                    settings_path, exc
                )
            )
        if not isinstance(data, dict):
            fail(
                "{} does not contain a JSON object at the top level; left unchanged".format(
                    settings_path
                )
            )
    try:
        existing_mode = stat.S_IMODE(os.stat(settings_path).st_mode)
    except OSError:
        existing_mode = None

env = data.get("env")
if env is None:
    env = {}
elif not isinstance(env, dict):
    fail(
        "{} has a non-object 'env' key; left unchanged".format(settings_path)
    )

env["ANTHROPIC_BASE_URL"] = base_url
env["ANTHROPIC_AUTH_TOKEN"] = master_key
data["env"] = env
data["alwaysThinkingEnabled"] = False

settings_dir = os.path.dirname(settings_path) or "."
fd, tmp_path = tempfile.mkstemp(prefix=".settings.json.", dir=settings_dir)
try:
    with os.fdopen(fd, "w") as tmp_file:
        json.dump(data, tmp_file, indent=2)
        tmp_file.write("\n")
    if existing_mode is not None:
        os.chmod(tmp_path, existing_mode)
    else:
        os.chmod(tmp_path, 0o600)
    os.replace(tmp_path, settings_path)
except OSError as exc:
    try:
        os.remove(tmp_path)
    except OSError:
        pass
    fail("failed to write {}: {}".format(settings_path, exc))

with open(status_path, "w") as status_file:
    status_file.write("ok\n")
PYEOF

if [ "$MERGE_EXIT" -ne 0 ] || [ ! -f "$MERGE_STATUS_FILE" ]; then
    fail_line "Failed to update $CLAUDE_SETTINGS_FILE"
    if [ -f "$MERGE_STATUS_FILE" ]; then
        cat "$MERGE_STATUS_FILE" >&2
    fi
    rm -f "$MERGE_STATUS_FILE"
    exit 1
fi

MERGE_STATUS="$(cat "$MERGE_STATUS_FILE")"
rm -f "$MERGE_STATUS_FILE"

    case "$MERGE_STATUS" in
        ok*)
            ok "Updated $CLAUDE_SETTINGS_FILE"
            ;;
        *)
            fail_line "${MERGE_STATUS#error: }"
            exit 1
            ;;
    esac
fi

# ------------------------------------------------------------------------
# 5. List available models.
# ------------------------------------------------------------------------

step "Available models"

if [ -f "$LITELLM_CONFIG_FILE" ]; then
    detail "Defined in litellm_config.yaml — use with --model exactly as shown:"
    printf '\n'
    while IFS= read -r model_name; do
        printf '  - %s\n' "$model_name"
    done <<EOF
$(grep -E '^[[:space:]]*-[[:space:]]*model_name:' "$LITELLM_CONFIG_FILE" | sed -E 's/^[[:space:]]*-[[:space:]]*model_name:[[:space:]]*//; s/\*+$//')
EOF
else
    warn "litellm_config.yaml not found; skipping model list"
fi

# ------------------------------------------------------------------------
# 6. Final summary.
# ------------------------------------------------------------------------

printf '\n%s\n' "${BOLD}Setup complete${RESET}"
printf '%s\n' "----------------------------------------"
if [ "${SKIP_CLAUDE_CONFIG:-0}" = "1" ]; then
    warn "Claude Code settings were not altered."
    detail "The proxy workflow will not work unless they are already configured."
    printf '\n'
fi
info "Next steps:"
printf '\n'
printf '  %s\n' "${BOLD}docker compose up -d${RESET}"
printf '  %s\n' "${BOLD}claude --model claude-sonnet-5${RESET}"
printf '\n'
detail "The proxy (docker compose) must stay running while you use Claude Code."
