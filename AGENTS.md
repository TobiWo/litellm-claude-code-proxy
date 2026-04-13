# AGENTS

This file provides guidance to AI Agents when working with code in this repository.

## Hard rules
- NEVER read the .env file

## Common commands

- Start proxy locally (loads `.env` automatically):
  - `./start_proxy.sh`
- Quick API check against local proxy:
  - `curl -X POST http://localhost:4000/v1/messages -H "Authorization: Bearer <LITELLM_MASTER_KEY>" -H "Content-Type: application/json" -d '{"model":"claude-sonnet-4-20250514","max_tokens":100,"messages":[{"role":"user","content":"Hello!"}]}'`
- Build Docker image:
  - `docker build -t litellm-claude-code-proxy .`
- Run Docker image with local env:
  - `docker run --env-file .env -p 4000:4000 litellm-claude-code-proxy`

## Architecture overview

This repository is a minimal configuration wrapper around LiteLLM Proxy.

- `start_proxy.sh` is the local runtime entrypoint:
  - Loads `.env` from repo root if present.
  - Resolves `LITELLM_PORT` (default `4000`).
  - Starts LiteLLM via `uv run --with "litellm[proxy]" litellm ...`.
  - Sets `UV_NATIVE_TLS=true` to use native/system TLS certs (important behind corporate proxies).

- `litellm_config.yaml` defines all request routing behavior:
  - `litellm_settings.master_key` enforces bearer-token auth for clients.
  - `model_list` uses `model_name: "*"` wildcard, so any incoming model name is accepted.
  - All traffic is forwarded to one Azure deployment specified by env vars:
    - `AZURE_OPENAI_DEPLOYMENT`
    - `AZURE_OPENAI_API_KEY`
    - `AZURE_OPENAI_ENDPOINT`
    - `AZURE_OPENAI_API_VERSION`

- `Dockerfile` is intentionally thin:
  - Uses official `docker.litellm.ai/berriai/litellm:main-stable` image.
  - Copies only config (`litellm_config.yaml`) into `/app/config.yaml`.
  - Runs LiteLLM with fixed default port/config arguments.

## Operational notes

- Local dev and Docker both depend on environment variables (see `.env.example`).
- Claude Code clients must point at the proxy with:
  - `ANTHROPIC_BASE_URL=http://localhost:4000`
  - `ANTHROPIC_AUTH_TOKEN=<LITELLM_MASTER_KEY>`
- There is no application code or test suite in this repo; behavior changes are primarily made by editing `litellm_config.yaml`, `.env`, and startup/runtime commands.