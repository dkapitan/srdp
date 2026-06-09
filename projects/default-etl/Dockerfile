FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

WORKDIR /app

# Copy dependency definition and lockfile first for layer caching
COPY pyproject.toml uv.lock README.md ./

# Copy platform library
COPY src/ src/

# Copy the ETL project
COPY projects/default-etl/ projects/default-etl/

# Install all deps (including srdp in editable mode)
RUN uv sync --frozen --no-dev --all-extras

ENV DAGSTER_HOME=/opt/dagster/dagster_home
ENV PYTHONPATH="/app/projects/default-etl/src:${PYTHONPATH}"
RUN mkdir -p "${DAGSTER_HOME}"

EXPOSE 3030

CMD ["uv", "run", "dagster", "code-server", "start", \
     "-h", "0.0.0.0", "-p", "3030", "-m", "etl.definitions"]
