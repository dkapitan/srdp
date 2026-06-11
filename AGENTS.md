# AGENTS.md — SRDP Codebase Guide for AI Coding Assistants

This file describes the structure and rules of the **Single Repo Data Platform (SRDP)** repository.

---

## What this repository is

SRDP assembles a modern open-source data platform (Zitadel, Traefik, Dagster, Polars/DuckDB, marimo, Quarto) into a single Git repository with two deployment targets: Docker Compose and Kubernetes (Helm + Scaleway Kapsule).

---

## Repository layout

```
srdp/
├── src/srdp/              # Platform library (IO managers, resources, base patterns)
├── projects/              # Client ETL projects (one per client/domain)
├── services/              # Runtime service images (marimo, quarto, traefik)
├── deploy/                # Deployment manifests (no business logic)
│   ├── docker/            # Docker Compose stack
│   ├── kubernetes/        # Helm umbrella chart
│   └── opentofu/          # GCP and Scaleway provisioning
├── config/                # Env-specific config (secrets gitignored)
└── docs/                  # Documentation source (Zensical)
```

---

## Hard rules

- Never commit secrets (`.env`, `secrets.sh`, `values-prod.yaml`, `kubeconfig.yaml`).
- Always use `just` as the task runner and `uv` as the package manager.
- No `pip`, `conda`, or `requirements.txt`.
- No `from __future__ import annotations`. Use native type hints (`str | None`, `list[int]`).
- No `print()` — use `logging.getLogger(__name__)`.
- No bare `except:` — always catch a specific exception type.
- No relative imports. Always use absolute imports.
- All configuration via Pydantic Settings, never `os.environ` directly.
- Reusable platform code belongs in `src/srdp/`, not in projects.

## Markdown

- Do not hard-wrap lines to a fixed column width. Write each sentence as a single line.
- Use em dashes sparingly; prefer commas, colons, or parentheses.
- Don't overuse bold, italics, or emojis.
- Check `zensical.toml` before suggesting markdown formatting or structure.

---

## Detailed instructions

Domain-specific conventions are in `.github/instructions/` and load automatically based on file context:

| File | Applies to |
|:---|:---|
| [`python.instructions.md`](.github/instructions/python.instructions.md) | All `*.py` files |
| [`dagster.instructions.md`](.github/instructions/dagster.instructions.md) | Dagster assets, definitions, IO managers |
| [`deploy.instructions.md`](.github/instructions/deploy.instructions.md) | Deploy manifests, services, Justfile |
