# 4. Production Deployment on Scaleway Kapsule (OpenTofu + Helm)

This runbook uses OpenTofu to provision infrastructure and Helm to deploy the chart on Scaleway Kapsule (mutualized). All `just` commands should be run from the **repository root**. Steps that require manual commands specify their working directory explicitly.

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
cd kubernetes/opentofu
source ./secrets.sh
./build-and-push.sh
```
This builds and pushes Marimo, Quarto, and srdp-etl (Dagster user code) to `rg.nl-ams.scw.cloud/srdp-registry`.

## 3) Provision infrastructure with OpenTofu
```bash
cd kubernetes/opentofu
tofu init -upgrade        # first run only, from kubernetes/opentofu/
cd ../..                  # back to repo root
just prod-apply
```

## 4) Export kubeconfig
```bash
just prod-use-kubeconfig   # from repo root
```

## 5) Prepare production Helm values
- Copy `kubernetes/srdp-chart/values-prod.example.yaml` to `kubernetes/srdp-chart/values-prod.yaml` if you are starting fresh.
- Fill in:
  - `global.domain` and `oauth2-proxy` cookie/whitelist domains (use a real domain or `<lb-ip>.nip.io` once you know the load balancer IP).
  - Zitadel master key, admin/user DB passwords, and OAuth2 client credentials.
  - ACME email for Traefik (Let's Encrypt).
  - In-cluster PostgreSQL passwords (`zitadel-db.auth.postgresPassword`, `zitadel-db.auth.password`).
- **Password complexity**: Zitadel enforces a password policy that requires uppercase, lowercase, digits, and at least one symbol. For example, use `SrdpTest123!` rather than `srdpTest123`.

The production values template enables PostgreSQL replication (`architecture: replication`) with a read replica. Daily backups via a CronJob are already configured in the base `values.yaml`.

## 6) Deploy with Helm (staged rollout)

### A. Bring up Traefik only (to get the LB IP)
```bash
just prod-traefik-only
```

### B. Update domains once the LB IP exists
```bash
just prod-get-values      # prints LOAD_BALANCER_IP
```
Replace every occurrence of the old LB IP in `values-prod.yaml` with `<LB_IP>.nip.io`. The fields that contain it are:
- `global.domain`
- `zitadel.zitadel.configmapConfig.ExternalDomain`
- `zitadel.zitadel.configmapConfig.firstInstance.org.human.email.address` (the `zitadel-admin@auth.…` address)
- `zitadel.login.customConfigmapConfig` — the `CUSTOM_REQUEST_HEADERS` value (`Host:auth.…` and `X-Zitadel-Public-Host:auth.…`)
- `oauth2-proxy.extraArgs`: `cookie-domain`, `whitelist-domain`, `oidc-issuer-url`, and the `Host:auth.…` header

### C. Enable Zitadel + OAuth2-Proxy
```bash
just prod-auth-only
```

### D. Configure Zitadel apps
- In Zitadel (`https://auth.<LB_IP>.nip.io/`), create OIDC apps for Marimo, Quarto, and Dagster with redirect URIs:
  - `https://marimo.<LB_IP>.nip.io/oauth2/callback`
  - `https://quarto.<LB_IP>.nip.io/oauth2/callback`
  - `https://dagster.<LB_IP>.nip.io/oauth2/callback`
- Copy the client ID/secret into `values-prod.yaml` (oauth2-proxy config section).

### E. Final deploy with all apps enabled
```bash
just prod-full
```

## Quick reference: full deployment flow

```bash
# 1. Prepare (first time only, from kubernetes/opentofu/)
cd kubernetes/opentofu && source ./secrets.sh && tofu init -upgrade

# 2. Build and push container images (from kubernetes/opentofu/)
cd kubernetes/opentofu && source ./secrets.sh && ./build-and-push.sh

# 3. Provision infrastructure (from repo root)
just prod-apply
just prod-use-kubeconfig

# 4. Staged Helm rollout (from repo root)
just prod-traefik-only
just prod-get-values                    # note the LOAD_BALANCER_IP
# → Update values-prod.yaml with LB IP in domain fields + secrets
just prod-auth-only
# → Configure Zitadel OIDC apps + copy client ID/secret into values-prod.yaml
just prod-full
```

## 7) Clean up

```bash
just prod-destroy
```

This runs `prod-uninstall` first (which deletes the Traefik LoadBalancer service to release the Scaleway-managed LB, then removes jobs, PVCs, and the Helm release) before running `tofu destroy` to remove the cluster and network infrastructure.

If you prefer manual commands:
```bash
# Delete the LB service first (Scaleway LB must be released before the private network can be destroyed)
export KUBECONFIG=kubernetes/opentofu/kubeconfig.yaml
kubectl delete svc srdp-traefik -n srdp --ignore-not-found
sleep 30
kubectl delete jobs --all -n srdp
kubectl delete pvc --all -n srdp
helm uninstall srdp -n srdp
cd kubernetes/opentofu && source ./secrets.sh && tofu destroy -auto-approve
```
