# LiteLLM Claude Code Proxy

Routes Claude Code through your GitHub Copilot subscription. Claude Code points at the local proxy as if it were Anthropic's API; LiteLLM translates and forwards requests to GitHub Copilot.

## Acknowledgments

This is a fork of [National Bank Belgium's LiteLLM Claude Code Proxy](https://github.com/NationalBankBelgium/litellm-claude-code-proxy). It is based on [dsebastiens tutorial](https://www.dsebastien.net/claude-code-on-github-copilot-subscription/). I optimized the workflow and the documentation quite a bit and extended for further shortcomings.

## License

The original upstream work remains under the [MIT License](LICENSE). All modifications and additions made in this fork are licensed under [PolyForm Noncommercial 1.0.0](LICENSE-MODIFICATIONS) — free for personal, educational, and other noncommercial use; commercial use of these changes requires permission from the author.

## Prerequisites

* A GitHub Copilot subscription (personal or enterprise)
* [uv](https://docs.astral.sh/uv/) installed
* Python 3.11–3.13 in PATH (3.14 is not supported — some dependency incompatibility)
* A virtual environment is recommended (conda, venv, etc.)
* Docker with the `docker compose` plugin (recommended; native fallback available)
* [Claude Code](https://docs.claude.com/en/docs/claude-code/setup) installed
* jq (only necessary if you want to fetch your own available models, see ["Note on available models"](#note-on-available-models-in-litellm_configyaml))

## Setup

```bash
./setup.sh
```

## Running with Docker Compose

Docker Compose is the recommended day-to-day runtime. It provides LiteLLM, PostgreSQL, persistence, restart policy, virtual keys, and spend tracking.

```bash
docker compose up -d
```

Starts the proxy on port `4000` (override with `LITELLM_PORT`) and PostgreSQL 18 with a persistent `pgdata` volume.

### Native fallback

If Docker/Compose is unavailable or unsuitable due to networking or corporate proxy behavior, start LiteLLM only:

```bash
./scripts/start_proxy.sh
```

Start Claude Code separately with either runtime:

```bash
claude --model claude-sonnet-5
```

### Stop / clean up

```bash
docker compose down        # stop containers (data preserved)
docker compose down -v     # stop containers and delete the database volume
```

## Choosing a model

It is recommended to always pass `--model` since the model picker in Claude Code's UI only reliably shows Haiku and Sonnet. For more information [see known limitations](#known-limitations).

```bash
claude --model <model_name>
```

### Note on available models in litellm_config.yaml

Your copilot licence might have more or different available models than listed in the respective config. Fetch the catalog for your subscription with:

```bash
./scripts/fetch_copilot_models.sh
```

Store the response in a file with:

```bash
./scripts/fetch_copilot_models.sh --output github-models.json
```

The helper uses the subscription-specific API endpoint and refreshes authentication once if the cached API token is rejected. It may show the browser device flow if no reusable authentication is available.

Each entry's `id` field is the exact string to use after `github_copilot/` in `litellm_params.model`. Each entry also lists `supported_endpoints` (see the next section, this determines whether you need extra config).

### Some models need extra config: `/responses` vs `/chat/completions`

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

## Known limitations

**Existing ENV variables:** Please be sure to not have any conflicting Claude Code / Anthropic env variables active in your .bashrc or .zshrc.

**Multi LLM provider setup:** This setup is specifically for GitHub Copilot. If you want to use multiple LLM providers like e.g. additionally connecting to native Anthropic API or Amazon Bedrock hosted Claude instances you need to do further manually editing of Claude Codes settings.json.

**Default model:** Claude Code defaults to `claude-opus-4-8` with 1M context. That variant is not in GitHub Copilot.

**Effort:** Claude code and copilot cli effort levels might not match perfectly. E.g. there is no `xhigh` or `max` effort available in copilot cli. I recommend to set default effort level to high via `"effortLevel": "high"` in `~/.claude/settings.json`. Try increasing effort manually via `/effort` in claude code and see if it works. From my experience this is indeed model dependent. Anthropic models understand all effort levels ofc. Not sure about GPT models.

**Litellm Proxy**: The litellm proxy always needs to be active when you want to use Claude Code.

## References

* [Claude Code on GitHub Copilot Subscription](https://www.dsebastien.net/claude-code-on-github-copilot-subscription/)
* [LiteLLM GitHub Copilot Provider](https://docs.litellm.ai/docs/providers/github_copilot)
* [Use Claude Code with Non-Anthropic Models](https://docs.litellm.ai/docs/tutorials/claude_non_anthropic_models)
* [LiteLLM Proxy Config Settings](https://docs.litellm.ai/docs/proxy/config_settings)
