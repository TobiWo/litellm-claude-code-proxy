FROM docker.litellm.ai/berriai/litellm:main-stable

COPY litellm_config.yaml /app/config.yaml

EXPOSE 4000

CMD ["--port", "4000", "--config", "/app/config.yaml"]
