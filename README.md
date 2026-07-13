# LiteLLM Claude Code Proxy

Routes Claude Code through your GitHub Copilot subscription. Claude Code points at the local proxy as if it were Anthropic's API; LiteLLM translates and forwards requests to GitHub Copilot.

## Acknowledgments

This is a fork of [National Bank Belgium's LiteLLM Claude Code Proxy](https://github.com/NationalBankBelgium/litellm-claude-code-proxy). It is based on [dsebastiens tutorial](https://www.dsebastien.net/claude-code-on-github-copilot-subscription/). I optimized the workflow and the documentation quite a bit and extended for further shortcomings.

## Prerequisites

* A GitHub Copilot subscription (personal or enterprise)
* [uv](https://docs.astral.sh/uv/) installed
* Python 3.11–3.13 in PATH (3.14 is not supported — some dependency incompatibility)
* A virtual environment is recommended (conda, venv, etc.)
* jq (only necessary if you want to fetch your own available models, see [Fetching your own available models](#fetching-your-own-available-models))

## Setup

### 1. Configure `.env`

```bash
cp .env.example .env
```

Edit `.env` if wanted:

```env
LITELLM_PORT=4000
LITELLM_MASTER_KEY=sk-foo-bar-baz
LITELLM_LOCAL_MODEL_COST_MAP=true

UI_USERNAME=litellm
UI_PASSWORD=litellm

POSTGRES_USER=litellm
POSTGRES_PASSWORD=litellm
POSTGRES_DB=litellm
```

| Variable | Description |
| --- | --- |
| `LITELLM_PORT` | Port for the proxy (default: `4000`) |
| `LITELLM_MASTER_KEY` | Bearer token clients use to authenticate against the proxy |
| `LITELLM_LOCAL_MODEL_COST_MAP` | Set to `true` to skip the remote cost map fetch (avoids SSL errors behind corporate proxies) |
| `UI_USERNAME` / `UI_PASSWORD` | Credentials for the LiteLLM admin UI at `/ui` |
| `POSTGRES_*` | PostgreSQL config (Docker Compose only) |

> **Security note:** The default values for `LITELLM_MASTER_KEY`, `UI_PASSWORD`, and `POSTGRES_PASSWORD` are not secure. Replace them if you expose the proxy beyond localhost.

### 2. First-run authentication

GitHub Copilot uses OAuth device flow. On first start, LiteLLM shows a URL and a device code. Open the URL, enter the code, done. The token goes to `~/.config/litellm/github_copilot/` and refreshes on its own.

**Option A (recommended):** run on your host:

```bash
./start_proxy.sh
```

This uses your active Python interpreter and runs LiteLLM in an isolated `uv` runtime, installing `litellm[proxy]` and the required DNS packages. Set `PYTHON_BIN` to use a specific interpreter.

> **Behind a corporate proxy?** Stick with Option A. Docker's bridge network has its own DNS resolver that may not reach GitHub's OAuth endpoints.

**Option B:** interactive Docker run:

```bash
docker run --rm -it \
  --env-file .env \
  -v "$(pwd)/litellm_config.yaml:/app/config.yaml:ro" \
  -v "$HOME/.config/litellm/github_copilot:/root/.config/litellm/github_copilot" \
  -p 4000:4000 \
  ghcr.io/berriai/litellm:v1.86.1 \
  --config /app/config.yaml --port 4000
```

Both options write the token to the same path, which [docker compose](#running-with-docker-compose) mounts into the container.

## Configuring Claude Code

Edit `~/.claude/settings.json` (or run `claude config`):

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:4000",
    "ANTHROPIC_AUTH_TOKEN": "<your-LITELLM_MASTER_KEY>"
  }
}
```

### Choosing a model

It is recommended to always pass `--model` since the model picker in Claude Code's UI only reliably shows Haiku and Sonnet. For more information [see known limitations](#known-limitations). So Haiku and Sonnet do not need `--model`, but everything else does. Use the `model_name` from [litellm_config.yaml](litellm_config.yaml), dropping the trailing `*`. Example: `model_name: claude-opus-4-7*` becomes `--model claude-opus-4-7`.

```bash
claude --model <model_name>
```

#### Note on available models in litellm_config.yaml

Your copilot licence might have more available models than listed in the respective config. I used the [litellm documentation](https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json) to find matching models. If litellm does not have a translation layer for the specific model, it can't be used.

#### Fetching your own available models

`model_prices_and_context_window.json` only carries cost/context-window metadata and lags behind what GitHub Copilot actually offers — it is not the source of truth for which models your subscription can use. To get the exact model IDs available to you, query the Copilot API directly with the same token VS Code/LiteLLM use:

1. Let LiteLLM complete the OAuth device flow once (see [First-run authentication](#2-first-run-authentication)) so `~/.config/litellm/github_copilot/api-key.json` exists.
2. Read the token and API host from that file:

   ```bash
   cat ~/.config/litellm/github_copilot/api-key.json | jq --indent 4
   ```

   It has an `.token` field (used as the bearer token) and an `.endpoints.api` field (the correct host for your plan — individual, business, or enterprise; this can differ from the generic `api.githubcopilot.com`).
3. Query the model catalog:

   ```bash
   curl -s "<endpoints.api>/models" \
     -H "Authorization: Bearer <token>" \
     -H "Copilot-Integration-Id: vscode-chat" \
     -H "Editor-Version: vscode/<your-installed-version>"
   ```

Each entry's `id` field is the exact string to use after `github_copilot/` in `litellm_params.model`. Each entry also lists `supported_endpoints` (see the next section, this determines whether you need extra config).

#### Some models need extra config: `/responses` vs `/chat/completions`

GitHub Copilot models don't all speak the same wire API. Check the `supported_endpoints` field from the model catalog response above:

* Models with `/chat/completions` in `supported_endpoints` (all current Claude models, most GPT models) work with a plain entry.
* Models with only `/responses` in `supported_endpoints` (e.g. the `gpt-5.3-codex`, `gpt-5.5`, and `gpt-5.6-*` family) need `model_info.mode: responses`, otherwise you get a `400 ... is not accessible via the /chat/completions endpoint` error:

  ```yaml
  - model_name: gpt-5-6-luna
    model_info:
      mode: responses
    litellm_params:
      model: github_copilot/gpt-5.6-luna
  ```

Since these Responses-API models get translated on the fly through Claude Code's Anthropic-style `/v1/messages` endpoint, expect the translation to be lossier than for native chat-completions models (e.g. streaming or tool-call edge cases).

### Verify with curl

```bash
curl -X POST http://localhost:4000/v1/messages \
  -H "Authorization: Bearer <your-LITELLM_MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-6",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## How it works

`litellm_config.yaml` maps incoming model names to GitHub Copilot models. Wildcard suffixes on `model_name` entries catch date-stamped variants like `claude-sonnet-4-6-20250514`. `start_proxy.sh` sets `UV_NATIVE_TLS=true` so the proxy uses the system certificate store, avoiding SSL errors behind corporate proxies.

## Running with Docker Compose

After OAuth, docker compose is how you run this day to day. It starts LiteLLM and PostgreSQL together; the database adds virtual keys and spend tracking. The OAuth token directory mounts from your host.

### Start

```bash
docker compose up -d
```

Starts the proxy on port `4000` (override with `LITELLM_PORT`) and PostgreSQL 18 with a persistent `pgdata` volume. The proxy waits for Postgres before starting.

### Stop / clean up

```bash
docker compose down        # stop containers (data preserved)
docker compose down -v     # stop containers and delete the database volume
```

## Known limitations

**Default model:** Claude Code defaults to `claude-opus-4-8` with 1M context. That variant is not in GitHub Copilot.

**Extended thinking:** Not supported via GitHub Copilot. Add `"alwaysThinkingEnabled": false` to `~/.claude/settings.json`.

**Effort:** Claude code and copilot cli effort levels might not match perfectly. E.g. there is no `xhigh` or `max` effort available in copilot cli. I recommend to set default effort level to high via `"effortLevel": "high"` in `~/.claude/settings.json`. Try increasing effort manually via `/effort` in claude code and see if it works.

**Litellm Proxy**: The litellm proxy always needs to be active when you want to use Claude Code.

## References

* [Claude Code on GitHub Copilot Subscription](https://www.dsebastien.net/claude-code-on-github-copilot-subscription/)
* [LiteLLM GitHub Copilot Provider](https://docs.litellm.ai/docs/providers/github_copilot)
* [Use Claude Code with Non-Anthropic Models](https://docs.litellm.ai/docs/tutorials/claude_non_anthropic_models)
* [LiteLLM Proxy Config Settings](https://docs.litellm.ai/docs/proxy/config_settings)
