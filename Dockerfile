FROM python:3.12-slim

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app

COPY litellm_config.yaml start_proxy.sh ./

RUN chmod +x start_proxy.sh

EXPOSE 4000

CMD ["./start_proxy.sh"]
