# Changelog

All notable changes to SRDP are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.2.0] - 2026-06-12

### Changed

- Restructured the repository into a monorepo layout: platform library in `src/srdp/`, client ETL projects in `projects/`, service images in `services/`, and all deployment manifests under `deploy/` (Docker Compose, Helm chart, OpenTofu). Prior layout had these spread across `docker/`, `kubernetes/`, and `docker/apps/`.
- Expanded `just` task runner with recipes for local dev, production deployment, linting, testing, and CI.
- Updated `AGENTS.md` with comprehensive coding conventions for contributors and AI assistants.

### Added

- `src/srdp/io/ducklake.py` — DuckLake IO manager backed by DuckDB and PostgreSQL.
- `src/srdp/io/storage.py` — Azure Blob Storage IO manager.
- `src/srdp/resources/k8s.py` — Kubernetes resource definitions for Dagster.
- `pyproject.toml` — proper monorepo package setup with `uv`.
- Architecture decision records (ADRs) in `docs/adr/` covering platform architecture, deployment model, auth, compute, and data organization.
- `.github/instructions/` — domain-specific coding instructions for Python, Dagster, and deploy targets.
- `SECURITY.md`, `CONTRIBUTING.md`, issue templates, and PR template.

## [0.1.0] - 2024-01-01

Initial release.

[Unreleased]: https://github.com/srdp-hub/srdp/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/srdp-hub/srdp/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/srdp-hub/srdp/releases/tag/v0.1.0
