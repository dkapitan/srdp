# 4. Production Deployment on Scaleway Kapsule (OpenTofu + Helm)

This runbook uses OpenTofu to provision infrastructure and Helm to deploy the chart on Scaleway Kapsule (mutualized). Commands assume you run them from the **repository root** unless otherwise noted.

## What OpenTofu provisions

OpenTofu creates the following resources on Scaleway (nl-ams region):
- A VPC and private network
- A Kapsule cluster (mutualized, k8s v1.32) with an autoscaling node pool (PLAY2-MICRO, 1-3 nodes)
- A security group allowing HTTP/HTTPS traffic

PostgreSQL runs **in-cluster** via the Bitnami Helm chart (not as a Scaleway managed database). The container registry (`srdp-registry`) must be created beforehand via the Scaleway Console.

## 1) Prepare cloud credentials
- Copy `kubernetes/opentofu/secrets.sh.example` to `kubernetes/opentofu/secrets.sh` and fill in your Scaleway credentials (SCW_ACCESS_KEY, SCW_SECRET_KEY, SCW_DEFAULT_PROJECT_ID).
- Load them before running OpenTofu:
  ```bash
  cd kubernetes/opentofu
  source ./secrets.sh
  ```

## 2) Build and push container images
Run the build script after sourcing credentials (it logs into the Scaleway registry):
```bash
source ./secrets.sh
./build-and-push.sh
```
This builds and pushes Marimo, Quarto, and srdp-etl (Dagster user code) to `rg.nl-ams.scw.cloud/srdp-registry`.

## 3) Provision infrastructure with OpenTofu
```bash
cd kubernetes/opentofu
tofu init -upgrade        # first run only
tofu apply -auto-approve
```

## 4) Export kubeconfig
```bash
tofu output -raw kubeconfig > kubeconfig.yaml
export KUBECONFIG=$(pwd)/kubeconfig.yaml
kubectl get nodes          # verify connectivity
```

## 5) Prepare production Helm values
- Copy `kubernetes/srdp-chart/values-prod.example.yaml` to `kubernetes/srdp-chart/values-prod.yaml` if you are starting fresh.
- Fill in:
  - `global.domain` and `oauth2-proxy` cookie/whitelist domains (use a real domain or `<lb-ip>.nip.io` once you know the load balancer IP).
  - Zitadel master key, admin/user DB passwords, and OAuth2 client credentials.
  - ACME email for Traefik (Let's Encrypt).
  - In-cluster PostgreSQL passwords (`zitadel-db.auth.postgresPassword`, `zitadel-db.auth.password`).

The production values template enables PostgreSQL replication (`architecture: replication`) with a read replica. Daily backups via a CronJob are already configured in the base `values.yaml`.

## 6) Deploy with Helm
All Helm commands below can be run from `kubernetes/` (or use the `just` recipes).

### A. Bring up Traefik only (to get the LB IP)
```bash
helm upgrade --install srdp srdp-chart \
  --namespace srdp --create-namespace \
  -f srdp-chart/values-prod.yaml \
  --set zitadel.enabled=false \
  --set oauth2-proxy.enabled=false \
  --set dagster.enabled=false \
  --set marimo.enabled=false \
  --set quarto.enabled=false
```

### B. Update domains once the LB IP exists
- Check the IP: `kubectl get svc srdp-traefik -n srdp`
- Set `global.domain`, `zitadel.zitadel.configmapConfig.ExternalDomain`, the `login.customConfigmapConfig` hosts, and the `oauth2-proxy.extraArgs` domain fields in `values-prod.yaml`, then re-run Helm.

### C. Enable Zitadel + OAuth2-Proxy
```bash
helm upgrade srdp srdp-chart \
  --namespace srdp --reset-values \
  -f srdp-chart/values-prod.yaml \
  --set zitadel.enabled=true \
  --set oauth2-proxy.enabled=true \
  --set dagster.enabled=false \
  --set marimo.enabled=false \
  --set quarto.enabled=false
```

### D. Configure Zitadel apps
- In Zitadel, create the OIDC apps for Marimo, Quarto, and Dagster with redirect URIs:
  - `https://marimo.<your-domain>/oauth2/callback`
  - `https://quarto.<your-domain>/oauth2/callback`
  - `https://dagster.<your-domain>/oauth2/callback`
- Update the client ID/secret in `values-prod.yaml` (oauth2-proxy config section).

### E. Final deploy with apps enabled
```bash
helm upgrade srdp srdp-chart \
  --namespace srdp --reset-values \
  -f srdp-chart/values-prod.yaml
```

## Example production flow with `just`
- `cd kubernetes/opentofu && source ./secrets.sh && tofu init -upgrade` (first time only)
- `cd kubernetes/opentofu && source ./secrets.sh && ./build-and-push.sh` (build and push container images)
- `just prod-apply`
- `just prod-use-kubeconfig`
- `just prod-traefik-only` (bring up Traefik to obtain the LB IP)
- `just prod-get-values` (prints `LOAD_BALANCER_IP`)
- Update `kubernetes/srdp-chart/values-prod.yaml` with the LB IP in domain fields plus your secrets (`ZITADEL_MASTER_KEY`, `PG_USER_PASS`, `ZITADEL_ADMIN_FIRST_PASS`, `OAUTH_COOKIE_SECRET`)
- `just prod-auth-only`
- In Zitadel (`https://auth.<LOAD_BALANCER_IP>.nip.io/`), create the Marimo, Quarto, and Dagster apps with redirects `https://marimo.<LOAD_BALANCER_IP>.nip.io/oauth2/callback`, `https://quarto.<LOAD_BALANCER_IP>.nip.io/oauth2/callback`, and `https://dagster.<LOAD_BALANCER_IP>.nip.io/oauth2/callback`, then copy the client ID/secret into `values-prod.yaml`
- `just prod-full`
- Clean up when finished: `just prod-uninstall` then `just prod-destroy`

## 7) Clean up
```bash
helm uninstall srdp -n srdp
kubectl delete jobs --all -n srdp
kubectl delete pvc --all -n srdp
cd kubernetes/opentofu && source ./secrets.sh && tofu destroy -auto-approve
```
