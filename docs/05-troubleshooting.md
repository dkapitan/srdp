# 5. Troubleshooting

### Ingress returns 404 or invalid cert
- Make sure the TLS secret `custom-ingress-cert` exists in the `srdp` namespace (`kubectl get secret custom-ingress-cert -n srdp`).
- Regenerate it with `mkcert` if the hostnames or IP changed.
- Confirm your hosts file points `auth/marimo/quarto.<domain>` to the Traefik IP.

### Pods stuck in `Pending`
- Check storage and DB connectivity: `kubectl describe pod <name> -n srdp`.
- For cloud deployments, verify the external DB host/port/password in `values-prod.yaml` match the OpenTofu outputs.

### LoadBalancer stays in `Pending`
- Traefik needs a LoadBalancer-capable environment. Verify your cloud account quotas and that the service type is `LoadBalancer` (see `values-prod.yaml`).

### OAuth login loops or 401s
- Ensure `global.domain`, `zitadel.zitadel.configmapConfig.ExternalDomain`, and the `oauth2-proxy` cookie/whitelist domains all match the URL you are using.
- Re-check the Zitadel client ID/secret and redirect URIs.

### Browser rejects the self-signed cert
- Import the `mkcert` root CA (printed during `mkcert -install`) or trust `kubernetes/certs/selfsigned.crt` locally while developing.
