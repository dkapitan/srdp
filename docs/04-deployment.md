# 4. Demo / Cloud Deployment (OpenTofu + Helm)

This runbook uses OpenTofu to provision infrastructure and Helm to deploy the chart. Commands assume you run them from `kubernetes/`.

## 1) Prepare cloud credentials
- Copy `kubernetes/opentofu/secrets.sh.example` to `kubernetes/opentofu/secrets.sh` and fill in your Scaleway credentials (SCW_ACCESS_KEY, SCW_SECRET_KEY, SCW_DEFAULT_PROJECT_ID, etc.).
- Load them before running OpenTofu:
  ```bash
  cd kubernetes/opentofu
  source ./secrets.sh
  ```
- The `just prod-*` targets read secrets from `kubernetes/opentofu/`; the image build script lives at `kubernetes/opentofu/build-and-push.sh` - run it after `source ./secrets.sh` so the registry credentials are loaded.

## 2) Provision infrastructure with OpenTofu
```bash
cd kubernetes/opentofu
tofu init -upgrade        # first run only
tofu apply -auto-approve
```

## 3) Export kubeconfig and DB outputs
```bash
tofu output -raw kubeconfig > kubeconfig.yaml
export KUBECONFIG=$(pwd)/kubeconfig.yaml

echo "DB_HOST: $(tofu output -raw rdb_host)"
echo "DB_PORT: $(tofu output -raw rdb_port)"
echo "DB_PASS: $(tofu output -raw rdb_password)"
```

## 4) Prepare production Helm values
- Copy `kubernetes/srdp-chart/values-prod.example.yaml` to `kubernetes/srdp-chart/values-prod.yaml` if you are starting fresh.
- Fill in:
  - `global.domain` and `oauth2-proxy` cookie/whitelist domains (use a real domain or `<lb-ip>.nip.io` once you know the load balancer IP).
  - Zitadel master key, admin/user DB passwords, and OAuth2 client credentials.
  - ACME email for Traefik if using Let's Encrypt.
  - Cloud DB host/port/password from the OpenTofu outputs above.

## 5) Deploy with Helm
All Helm commands below can be run from `kubernetes/` (or use the `just` recipes).

### A. Bring up Traefik only (to get the LB IP)
```bash
helm upgrade --install srdp srdp-chart \
  --namespace srdp --create-namespace \
  -f srdp-chart/values-prod.yaml \
  --set zitadel.enabled=false \
  --set oauth2-proxy.enabled=false \
  --set marimo.enabled=false \
  --set quarto.enabled=false
```

### B. Update domains once the LB IP exists
- Check the IP: `kubectl get svc srdp-traefik -n srdp`
- Set `global.domain`, `zitadel.zitadel.configmapConfig.ExternalDomain`, and the `oauth2-proxy.extraArgs` domain fields in `values-prod.yaml`, then re-run Helm.

### C. Enable Zitadel + OAuth2-Proxy
```bash
helm upgrade srdp srdp-chart \
  --namespace srdp \
  -f srdp-chart/values-prod.yaml \
  --set zitadel.enabled=true \
  --set oauth2-proxy.enabled=true \
  --set marimo.enabled=false \
  --set quarto.enabled=false
```

### D. Configure Zitadel apps
- In Zitadel, create the OIDC apps for Marimo and Quarto with redirect URIs:
  - `https://marimo.<your-domain>/oauth2/callback`
  - `https://quarto.<your-domain>/oauth2/callback`
- Update the client ID/secret in `values-prod.yaml` (oauth2-proxy config section).

### E. Final deploy with apps enabled
```bash
helm upgrade srdp srdp-chart \
  --namespace srdp \
  -f srdp-chart/values-prod.yaml
```

## Example production flow with `just`
- `just prod-apply`
- `just prod-use-kubeconfig`
- `just prod-traefik-only` (bring up Traefik to obtain the LB IP)
- `just prod-get-values` (prints `LOAD_BALANCER_IP`, `DB_HOST`, `DB_PORT`, `DB_PASS`)
- Update `kubernetes/srdp-chart/values-prod.yaml` with the dynamic values above plus your secrets (`ZITADEL_MASTER_KEY`, `PG_USER_PASS`, `ZITADEL_ADMIN_FIRST_PASS`, `OAUTH_COOKIE_SECRET`)
- `just prod-auth-only`
- In Zitadel (`https://auth.<LOAD_BALANCER_IP>.nip.io/`), create the Marimo and Quarto apps with redirects `https://marimo.<LOAD_BALANCER_IP>.nip.io/oauth2/callback` and `https://quarto.<LOAD_BALANCER_IP>.nip.io/oauth2/callback`, then copy the client ID/secret into `values-prod.yaml`
- `just prod-full`
- Clean up when finished: `just prod-uninstall` then `just prod-destroy`

## 6) Clean up
```bash
helm uninstall srdp -n srdp
kubectl delete jobs --all -n srdp
kubectl delete pvc --all -n srdp
cd kubernetes/opentofu && source ./secrets.sh && tofu destroy -auto-approve
```
