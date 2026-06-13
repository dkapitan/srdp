---
title: 2. Local Configuration & Setup
icon: lucide/locate-fixed
---

# Local Configuration & Setup

This guide will walk you through the steps to get the Single Repo Data Platform (SRDP) running on your local machine. There are two options:

- **Docker Compose** — simplest, no Kubernetes needed, good for trying out the stack locally.
- **Kubernetes (Helm)** — closer to the production setup, requires a local cluster.

Both options require mkcert for local TLS certificates and `/etc/hosts` entries for the `*.local.dev` domains.

---

## Option A: Docker Compose

### 1) Clone the repo

```bash
git clone git@github.com:srdp-hub/srdp.git # or git clone https://github.com/srdp-hub/srdp.git
cd srdp
```

### 2) Point DNS at localhost

Add the following line to your hosts file (`/etc/hosts` on macOS/Linux):

```
127.0.0.1 auth.local.dev marimo.local.dev quarto.local.dev dagster.local.dev
```

### 3) Install the local CA and generate TLS certificates

The stack serves everything over HTTPS because Zitadel and OAuth2-Proxy require it. [`mkcert`](https://github.com/FiloSottaro/mkcert) creates locally-trusted certificates so your browser won't show warnings.

```bash
brew install mkcert   # or see mkcert docs for other platforms
mkcert -install       # one-time: installs a local Certificate Authority
just docker-tls       # generates certs in deploy/docker/certs/
```

### 4) Create the environment file

```bash
cp deploy/docker/.env.example deploy/docker/.env
```

The defaults in `.env.example` are fine for local development. You will need to update `OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET` after Zitadel creates the OIDC application on first boot (see [03-usage.md](./03-usage.md)).

### 5) Start the stack

```bash
just docker-up
```

This builds the Marimo and Quarto images locally and starts all services: Traefik, PostgreSQL, Zitadel, OAuth2-Proxy, Marimo, and Quarto. First run will take a few minutes while images are pulled and built.

To stop the stack:

```bash
just docker-down
```

> **Warning:** Do not run `docker compose down -v` unless you want to destroy all persistent data, including your Zitadel configuration.

---

## Option B: Kubernetes (Helm)

### 1) Clone the repo

```bash
git clone git@github.com:srdp-hub/srdp.git # or git clone https://github.com/srdp-hub/srdp.git
cd srdp
```

### 2) Point DNS at your cluster

The chart uses `*.local.dev` by default. Point those hostnames at the IP you will use to reach Traefik:

- For NodePort/local clusters: `127.0.0.1` is usually fine.
- For a LoadBalancer: use the external IP once Traefik comes up.

Add one line to your hosts file (`/etc/hosts` on macOS/Linux):

```
127.0.0.1 auth.local.dev marimo.local.dev quarto.local.dev dagster.local.dev
```

### 3) Install the local CA and generate TLS certificates

```bash
brew install mkcert   # or see mkcert docs for other platforms
mkcert -install       # one-time: installs a local Certificate Authority
just local-tls        # generates certs and creates the k8s TLS secret
```

Or manually:

```bash
mkdir -p deploy/kubernetes/certs
mkcert -cert-file deploy/kubernetes/certs/selfsigned.crt -key-file deploy/kubernetes/certs/selfsigned.key \
  "auth.local.dev" "marimo.local.dev" "quarto.local.dev" "dagster.local.dev"

kubectl create namespace srdp --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret tls custom-ingress-cert \
  --namespace srdp \
  --key deploy/kubernetes/certs/selfsigned.key \
  --cert deploy/kubernetes/certs/selfsigned.crt \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 4) Build local container images

The Helm chart references three application images. For local development the pull policy is set to `Never`, so the images must exist in your local Docker/containerd cache:

```bash
docker build -t rg.nl-ams.scw.cloud/srdp-registry/marimo:v1.0 services/marimo
docker build -t rg.nl-ams.scw.cloud/srdp-registry/quarto:v1.0 services/quarto
docker build -t rg.nl-ams.scw.cloud/srdp-registry/srdp-etl:v1.0 -f projects/default-etl/Dockerfile .
```

> **Docker Desktop users:** `pullPolicy: Never` does not work with Docker Desktop's Kubernetes. Docker Desktop runs its own containerd instance for Kubernetes that is separate from the Docker daemon, so images built with `docker build` are not visible to the cluster. Use a local registry instead:
>
> 1. Add `"insecure-registries": ["host.docker.internal:5001"]` to Docker Desktop → Settings → Docker Engine, then Apply & Restart.
> 2. Start a local registry: `docker run -d -p 5001:5000 --restart=always --name local-registry registry:2`
> 3. Tag and push your images:
>    ```bash
>    for img in marimo quarto srdp-etl; do
>      docker tag rg.nl-ams.scw.cloud/srdp-registry/${img}:v1.0 localhost:5001/${img}:v1.0
>      docker push localhost:5001/${img}:v1.0
>    done
>    ```
> 4. Override the image references and pull policy in `values-local.yaml`:
>    ```yaml
>    marimo:
>      image:
>        repository: host.docker.internal:5001/marimo
>        tag: "v1.0"
>        pullPolicy: IfNotPresent
>    quarto:
>      image:
>        repository: host.docker.internal:5001/quarto
>        tag: "v1.0"
>        pullPolicy: IfNotPresent
>    dagster:
>      dagster-user-deployments:
>        deployments:
>          - name: srdp-etl
>            image:
>              repository: host.docker.internal:5001/srdp-etl
>              tag: "v1.0"
>              pullPolicy: IfNotPresent
>    ```
>
> If you see `ErrImagePull` with `unexpected status from HEAD request to http://registry-mirror:1273/...`, Docker Desktop's internal mirror is intercepting the pull. Create a per-registry override inside the Kubernetes node:
> ```bash
> docker run --rm --privileged --pid=host debian nsenter -t <containerd-pid> -m -- bash -c "
>   mkdir -p /etc/containerd/certs.d/host.docker.internal:5001
>   cat > /etc/containerd/certs.d/host.docker.internal:5001/hosts.toml << 'EOF'
> server = \"http://host.docker.internal:5001\"
> [host.\"http://host.docker.internal:5001\"]
>   capabilities = [\"pull\", \"resolve\"]
>   skip_verify = true
> EOF
> "
> ```
> Find the PID of `/usr/local/bin/containerd` (the k8s one, not Docker's) with:
> ```bash
> docker run --rm --privileged --pid=host debian nsenter -t 1 -m -- ps aux | grep '/usr/local/bin/containerd' | grep -v shim
> ```
> Note this override lives inside the Docker Desktop VM and **does not survive a Docker Desktop restart**.
>
> **Recommendation:** For frequent local Kubernetes development, [kind](https://kind.sigs.k8s.io/) or [minikube](https://minikube.sigs.k8s.io/) avoid all of this — they provide `kind load docker-image` and `minikube image load` respectively.

### 5) Fill in secrets and local values

Update `deploy/kubernetes/srdp-chart/values-local.yaml` before installing:

- set your own Zitadel master key, DB passwords, OAuth2 client values, and cookie secret
- keep `custom-ingress-cert` (created above) or point to another TLS secret if you prefer.

### 6) Install the chart locally

```bash
cd deploy/kubernetes/srdp-chart
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

### 7) Configure the OAuth2 client in Zitadel

The `clientID` and `clientSecret` in `values-local.yaml` must match an OIDC app in your Zitadel instance. The values committed to the repo are placeholders — a fresh Zitadel deployment will not recognise them, causing a `{"error":"invalid_request","error_description":"Errors.App.NotFound"}` error when you first open a service URL.

After the chart is deployed, create the app via the Zitadel management API using the `iam-admin-pat` secret the setup job creates:

```bash
PAT=$(kubectl get secret -n srdp iam-admin-pat -o jsonpath='{.data.pat}' | base64 -d)

PROJECT_ID=$(curl -sk -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" \
  -d '{"name":"srdp"}' https://auth.srdp.localhost/management/v1/projects \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

curl -sk -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" \
  -d '{
    "name": "oauth2-proxy",
    "redirectUris": [
      "https://marimo.srdp.localhost/oauth2/callback",
      "https://quarto.srdp.localhost/oauth2/callback",
      "https://dagster.srdp.localhost/oauth2/callback"
    ],
    "responseTypes": ["OIDC_RESPONSE_TYPE_CODE"],
    "grantTypes": ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"],
    "appType": "OIDC_APP_TYPE_WEB",
    "authMethodType": "OIDC_AUTH_METHOD_TYPE_BASIC",
    "accessTokenType": "OIDC_TOKEN_TYPE_BEARER"
  }' "https://auth.srdp.localhost/management/v1/projects/$PROJECT_ID/apps/oidc"
```

Copy the `clientId` and `clientSecret` from the response into `values-local.yaml` under `oauth2-proxy.config`, then run `just local-deploy` again.

The chart deploys the full stack: Traefik, PostgreSQL (in-cluster via Bitnami Helm chart), Zitadel, OAuth2-Proxy, Dagster (webserver + daemon + user code), Marimo, and Quarto. PostgreSQL hosts both the `zitadel` and `dagster` databases, created automatically via `zitadel-db.primary.initdb.scripts`.
**Congratulations! The local environment should now be up and running.** Proceed to the next section, **Usage & Verification**, to confirm that everything is working correctly.
