# 3. Usage & Verification

### Check the release
- `helm list -n srdp`
- `kubectl get pods,svc,ing -n srdp`

### Access services
- Marimo: `https://marimo.local.dev`
- Quarto: `https://quarto.local.dev`
- Dagster: `https://dagster.local.dev`
- Zitadel: `https://auth.local.dev`
- Traefik dashboard (if enabled in values): `http://localhost:8080`

All apps (Marimo, Quarto, Dagster) are protected behind OAuth2-Proxy. Accessing any of them will redirect to Zitadel for OIDC login before granting access.

### Update or remove the release
- Re-apply updated values: rerun the `helm upgrade --install ...` command from [02-configuration.md](./02-configuration.md) (or `just local-deploy`).
- Remove everything: `helm uninstall srdp -n srdp`
  - If you also want to clear persistent data: `kubectl delete pvc --all -n srdp`
- Or use the task runner: `just local-delete`

### Logs
- Watch all pods: `kubectl logs -n srdp -l app.kubernetes.io/instance=srdp -f`
- Specific service, e.g. Marimo: `kubectl logs -n srdp deploy/marimo -f`
- Dagster webserver: `kubectl logs -n srdp deploy/srdp-dagster-webserver -f`
- Dagster daemon: `kubectl logs -n srdp deploy/srdp-dagster-daemon -f`
