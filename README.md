# LiteLLM Claude Code Proxy

A LiteLLM proxy that routes any model request to your Azure AI Foundry deployment. Useful for running Claude Code against an AI model hosted on Azure Foundry.

## Prerequisites

- [uv](https://docs.astral.sh/uv/) installed
- An Azure AI Foundry deployment with an API key

## Setup

### 1. Create the `.env` file

```bash
cp .env.example .env
```

Edit `.env` and fill in your values:

```env
AZURE_OPENAI_ENDPOINT=
AZURE_OPENAI_API_KEY=
AZURE_OPENAI_DEPLOYMENT=azure/responses/gpt-5.3-codex
AZURE_OPENAI_API_VERSION=preview

LITELLM_PORT=4000
LITELLM_MASTER_KEY=sk-foo-bar-baz
LITELLM_LOCAL_MODEL_COST_MAP=true
```

| Variable | Description |
|---|---|
| `AZURE_OPENAI_ENDPOINT` | Your Azure AI Foundry endpoint URL |
| `AZURE_OPENAI_API_KEY` | API key for the endpoint |
| `AZURE_OPENAI_DEPLOYMENT` | Model deployment name with provider prefix (e.g. `azure/responses/gpt-5.3-codex`) |
| `AZURE_OPENAI_API_VERSION` | Azure API version (`preview` for Codex models, or a dated version like `2025-03-01-preview`) |
| `LITELLM_PORT` | Port for the proxy (default: `4000`) |
| `LITELLM_MASTER_KEY` | Auth token for the proxy — used by clients to authenticate against the LiteLLM proxy |
| `LITELLM_LOCAL_MODEL_COST_MAP` | Set to `true` to skip fetching the remote cost map (avoids SSL errors behind corporate proxies) |

### 2. Start the proxy

```bash
./start_proxy.sh
```

The proxy starts on port **4000** by default. Override with `LITELLM_PORT` in your `.env`.

### 3. Use with Claude Code

In a separate terminal:

```bash
export ANTHROPIC_BASE_URL=http://localhost:4000
export ANTHROPIC_AUTH_TOKEN=<your-LITELLM_MASTER_KEY>
claude
```

## Configuring Claude Code

Claude Code needs two environment variables to connect through the proxy. You can set them in different ways depending on your workflow.

See also the official LiteLLM guide: [Use Claude Code with Non-Anthropic Models](https://docs.litellm.ai/docs/tutorials/claude_non_anthropic_models).

### Option A: Environment variables (per session)

Set them in your shell before launching Claude Code:

```bash
export ANTHROPIC_BASE_URL=http://localhost:4000
export ANTHROPIC_AUTH_TOKEN=<your-LITELLM_MASTER_KEY>
claude
```

### Option B: Claude Code settings (persistent)

Run `claude config` or edit `~/.claude/settings.json`:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:4000",
    "ANTHROPIC_AUTH_TOKEN": "<your-LITELLM_MASTER_KEY>"
  }
}
```

This persists across sessions so you don't need to export variables each time.

### Option C: VS Code settings (for Copilot Chat with Claude Code)

Add to your VS Code `settings.json`:

```json
{
  "claude-code.env": {
    "ANTHROPIC_BASE_URL": "http://localhost:4000",
    "ANTHROPIC_AUTH_TOKEN": "<your-LITELLM_MASTER_KEY>"
  }
}
```

### Choosing a model

By default Claude Code picks a model name like `claude-sonnet-4-20250514`. Since the proxy uses a wildcard, any model name is accepted and routed to your Azure deployment. You can also specify a model explicitly:

```bash
claude --model gpt-5.3-codex
```

### 4. Verify with curl

```bash
curl -X POST http://localhost:4000/v1/messages \
  -H "Authorization: Bearer <your-LITELLM_MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## How it works

The `litellm_config.yaml` uses a wildcard (`model_name: "*"`) so any model name sent by the client is routed to your single Azure deployment. The `start_proxy.sh` script uses `uv run` with `UV_NATIVE_TLS=true` to use the system certificate store, avoiding SSL issues behind corporate proxies.

## Running with Docker

The Dockerfile uses the [official LiteLLM Docker image](https://docs.litellm.ai/docs/proxy/deploy) — no need to install uv or Python separately.

### Build the image

```bash
docker build -t litellm-claude-code-proxy .
```

### Run the container

```bash
docker run --env-file .env -p 4000:4000 litellm-claude-code-proxy
```

Or skip the build entirely and run the official image directly:

```bash
docker run \
  --env-file .env \
  -v $(pwd)/litellm_config.yaml:/app/config.yaml \
  -p 4000:4000 \
  docker.litellm.ai/berriai/litellm:main-stable \
  --config /app/config.yaml --port 4000
```

The container reads all configuration from environment variables via the `.env` file.

## References

- [LiteLLM Documentation](https://docs.litellm.ai/)
- [Proxy Quick Start](https://docs.litellm.ai/docs/proxy/quick_start)
- [Proxy CLI](https://docs.litellm.ai/docs/proxy/cli)
- [Proxy Config Settings](https://docs.litellm.ai/docs/proxy/config_settings)
- [Docker Quick Start & Model List Specification](https://docs.litellm.ai/docs/proxy/docker_quick_start#model-list-specification)
- [Use Claude Code with Non-Anthropic Models](https://docs.litellm.ai/docs/tutorials/claude_non_anthropic_models)
