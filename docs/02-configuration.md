---
title: 2. Local Configuration & Setup
icon: lucide/locate-fixed
---

# Local Configuration & Setup

This guide will walk you through the steps to get the Single Repo Data Platform (SRDP) running on your local machine.

## 1) Clone the repo

```bash
git clone git@github.com:dkapitan/srdp.git # or git clone https://github.com/dkapitan/srdp.git
cd srdp
```

## 2) Point DNS at your cluster

The chart uses `*.local.dev` by default. Point those hostnames at the IP you will use to reach Traefik:
- For NodePort/local clusters: `127.0.0.1` is usually fine.
- For a LoadBalancer: use the external IP once Traefik comes up.

Add one line to your hosts file:
```
127.0.0.1 auth.local.dev marimo.local.dev quarto.local.dev dagster.local.dev
```

## 3) Create a local TLS secret

Generate a certificate for the local domains and create the secret that the Helm chart expects.
```bash
mkdir -p kubernetes/certs
mkcert -cert-file kubernetes/certs/selfsigned.crt -key-file kubernetes/certs/selfsigned.key \
  "auth.local.dev" "marimo.local.dev" "quarto.local.dev" "dagster.local.dev"

# Apply the secret into your target namespace (default here is srdp)
kubectl create namespace srdp --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret tls custom-ingress-cert \
  --namespace srdp \
  --key kubernetes/certs/selfsigned.key \
  --cert kubernetes/certs/selfsigned.crt \
  --dry-run=client -o yaml | kubectl apply -f -
```

Or simply run:
```bash
just local-tls
```

## 4) Build local container images

The Helm chart references three application images. For local development the pull policy is set to `Never`, so the images must exist in your local Docker/containerd cache:

```bash
docker build -t rg.nl-ams.scw.cloud/srdp-registry/marimo:v1.0 local/apps/marimo
docker build -t rg.nl-ams.scw.cloud/srdp-registry/quarto:v1.0 local/apps/quarto
docker build -t rg.nl-ams.scw.cloud/srdp-registry/srdp-etl:v1.0 kubernetes/apps/srdp-etl
```

## 5) Fill in secrets and local values

Update `kubernetes/srdp-chart/values-local.yaml` before installing:
- set your own Zitadel master key, DB passwords, OAuth2 client values, and cookie secret
- keep `custom-ingress-cert` (created above) or point to another TLS secret if you prefer.

## 6) Install the chart locally

```bash
cd kubernetes/srdp-chart
helm dependency update
helm upgrade --install srdp . \
  --namespace srdp --create-namespace \
  -f values.yaml \
  -f values-local.yaml
```

Or simply run:
```bash
just local-deploy
```

To re-run with updated values, run the same `helm upgrade` command (or `just local-deploy`).

The chart deploys the full stack: Traefik, PostgreSQL (in-cluster via Bitnami Helm chart), Zitadel, OAuth2-Proxy, Dagster (webserver + daemon + user code), Marimo, and Quarto. PostgreSQL hosts both the `zitadel` and `dagster` databases, created automatically via `zitadel-db.primary.initdb.scripts`.
**Congratulations! The local environment should now be up and running.** Proceed to the next section, **Usage & Verification**, to confirm that everything is working correctly.
