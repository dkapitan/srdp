---
title: 7. Contributing
icon: lucide/git-pull-request
---

# Contributing

## Getting started

```bash
git clone https://github.com/srdp-hub/srdp.git
cd srdp
uv sync
pre-commit install
uv run pytest
```

## Branching

We use GitHub Flow: feature branches from `main`, merged via PR.

Branch naming: `<category>/<description>` (e.g., `feat/ducklake-io`, `fix/helm-pvc`, `docs/deployment`).

## Pull requests

- Describe what the PR does and why.
- Keep PRs focused on one logical change.
- Ensure CI passes.
- Update docs if behavior changes.

## Versioning

We follow [Semantic Versioning](https://semver.org/):

- **Patch**: bug fixes, security dependency bumps.
- **Minor**: new features, non-breaking changes.
- **Major**: breaking changes to public APIs or data formats.

Documentation-only changes, CI updates, and test additions do not bump the version.

## Architectural Decision Records (ADRs)

Significant, hard-to-reverse decisions (choosing a component, changing a core interface, adopting a new pattern) should be recorded as an ADR in `docs/adr/`.

**When to write one:**

- You're choosing between multiple realistic options with real trade-offs.
- The decision will be difficult or costly to reverse later.
- Future contributors would otherwise wonder *why* the project is structured this way.

**When you don't need one:** bug fixes, refactors that don't change behaviour, dependency bumps, or any decision that's obvious from the code.

**How to add an ADR:**

1. Copy [`docs/adr/0000-adr-template.md`](https://github.com/srdp-hub/srdp/blob/main/docs/adr/0000-adr-template.md) to `docs/adr/NNNN-short-title.md`, using the next available number.
2. Fill in the context, options considered, and the chosen outcome with justification.
3. Set `status: proposed` in the frontmatter; it moves to `accepted` once the PR merges.

We follow the [MADR](https://adr.github.io/madr/) format.

## CI/CD

CI runs on GitHub Actions. The current workflow:

- **`docs.yml`**: builds and deploys documentation to GitHub Pages on push to `main` (paths: `docs/`).

Planned workflows:

- **`ci.yml`**: lint (ruff), type check (ty), test (pytest), security audit (uv-secure) on every PR.
- **`images.yml`**: build and push container images to Scaleway Container Registry on push to `main`.
- **`deploy.yml`**: `helm upgrade` against production using kubeconfig stored as a GitHub Actions secret.

Production deployments can also be triggered manually via `just prod-full` as a fallback.

## AI-assisted contributions

We follow the [Linux Foundation policy on generative AI](https://www.linuxfoundation.org/legal/generative-ai): AI-generated code is treated the same as any other contribution.

1. **You own your commits.** Review, understand, and validate before committing.
2. **License compliance.** Ensure AI output does not conflict with Apache-2.0.
3. **No special process.** Same PR review as any other change.

### Agent configuration

- [`AGENTS.md`](https://github.com/srdp-hub/srdp/blob/main/AGENTS.md) at the repo root provides the project overview, hard rules, and links to specifics.
- `.github/instructions/*.md` contains domain-specific instructions that load based on file patterns.
- `.github/copilot-instructions.md` references `AGENTS.md` for GitHub Copilot integration.

### Guidelines for maintaining agent instructions

The top-level `AGENTS.md` should stay under 50 lines. Overloaded instruction files cause agents to lose focus and ignore important rules.

**Structure it hierarchically:**

1. `AGENTS.md` contains only the essentials: one-line project description, condensed repo layout, 5-10 hard rules, and links to detail files.
2. `.github/instructions/` files contain domain-specific conventions (Python style, Dagster patterns, Helm and deployment context). Each file declares an `applyTo` glob so it only loads when the agent is working on matching files.

**Good candidates for agent instructions:**

- Project-specific constraints an agent cannot infer from config or code (e.g., "always use `uv`, never `pip`").
- Framework conventions with one concise example.
- Hard boundaries ("never commit secrets", "no bare `except:`").

**Avoid putting these in agent instructions:**

- Anything already expressed in `pyproject.toml`, ruff config, or linter rules.
- Full documentation or runbooks. Link to the docs site instead.
- Version numbers or URLs that change frequently.
