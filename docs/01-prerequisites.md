---
title: 1. Prerequisites
icon: lucide/list-todo
---

# Prerequisites

Before you begin, ensure you have the following software installed on your local machine. This guide assumes you have a basic understanding of using the command line.

Required tools (all deployment methods)
- Git
- Container runtime (Docker Engine + Docker Compose)
- [`just`](https://github.com/casey/just) — task runner for common commands
- [`mkcert`](https://github.com/FiloSottaro/mkcert) — local TLS certificates for `*.srdp.localhost`

Additional tools for Kubernetes deployment
- `kubectl` + a Kubernetes cluster (tested with 1.32+)
- Helm 3.x

Additional tools for production
- [OpenTofu](https://opentofu.org/docs/intro/install/) — infrastructure provisioning on Scaleway Kapsule

Tested with
- **macOS**: Docker Engine + Docker Compose + Kubernetes via [Colima](https://github.com/abiosoft/colima)
- **Linux**: Docker Engine + Docker Compose + Kubernetes (native)

Notes
- The `just` recipes require a Bash-compatible shell.
- You need permission to create namespaces/secrets and, for cloud runs, to provision load balancers.
