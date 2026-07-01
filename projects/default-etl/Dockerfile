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
# Put the uv venv on PATH so entry points (dagster) resolve without `uv run`.
# The Dagster Helm chart invokes the bare `dagster` binary for its gRPC server
# and health probe, bypassing the CMD below. This is uv's documented pattern
# for "activating" a venv in an image (astral-sh/uv Docker guide).
ENV PATH="/app/.venv/bin:${PATH}"
RUN mkdir -p "${DAGSTER_HOME}"

EXPOSE 3030

CMD ["uv", "run", "dagster", "code-server", "start", \
     "-h", "0.0.0.0", "-p", "3030", "-m", "etl.definitions"]
