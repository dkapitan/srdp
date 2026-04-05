---
title: 1. Prerequisites
icon: lucide/list-todo
---

# Prerequisites

Before you begin, ensure you have the following software installed on your local machine. This guide assumes you have a basic understanding of using the command line.

Required tools
- Git
- Container runtime (Docker/Podman) for building the Marimo, Quarto, and srdp-etl (Dagster user code) images
- Kubernetes cluster + `kubectl` (tested with 1.32+). For local work, `kind`, `minikube`, or `k3d` with LoadBalancer/NodePort access all work.
- Helm 3.x
- [`just`](https://github.com/casey/just) as a task runner for the common Helm/OpenTofu commands in this repo
- [`mkcert`](https://github.com/FiloSottile/mkcert) to generate local TLS certificates for `*.local.dev`
- [OpenTofu](https://opentofu.org/docs/intro/install/) for production infrastructure on Scaleway Kapsule

Notes
- The `just` recipes use a Bash-compatible shell; on Windows, run them from Git Bash or WSL.
- You need permission to create namespaces/secrets and, for cloud runs, to provision load balancers.
