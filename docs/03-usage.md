# 3. Usage & Verification

### Check the release
- `helm list -n srdp`
- `kubectl get pods,svc,ing -n srdp`

### Access services
- Marimo: `https://marimo.local.dev`
- Quarto: `https://quarto.local.dev`
- Zitadel: `https://auth.local.dev`
- Traefik dashboard (if enabled in values): `http://localhost:8080`

### Update or remove the release
- Re-apply updated values: rerun the `helm upgrade --install ...` command from [02-configuration.md](./02-configuration.md) (or `just local-deploy`).
- Remove everything: `helm uninstall srdp -n srdp`
  - If you also want to clear persistent data: `kubectl delete pvc --all -n srdp`

### Logs
- Watch all pods: `kubectl logs -n srdp -l app.kubernetes.io/instance=srdp -f`
- Specific service, e.g. Marimo: `kubectl logs -n srdp deploy/marimo -f`
