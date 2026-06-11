FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

WORKDIR /app

RUN uv pip install --system marimo>=0.13

COPY notebooks/ .

EXPOSE 8000

CMD ["marimo", "run", "app.py", "--host", "0.0.0.0", "--port", "8000"]