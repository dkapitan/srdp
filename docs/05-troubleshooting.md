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

### ACME errors / rate limits
- Let’s Encrypt blocks `nip.io` frequently and requires public reachability on ports 80/443. Open those ports on the load balancer/security group, or temporarily point Traefik to the staging CA until production issuance succeeds.

### Zitadel login-client missing
- If the Postgres DB already contains Zitadel data, the `login-client` PAT will not be recreated. Use a fresh database (or drop the existing schema) before re-running the chart.

### Traefik stuck in Init
- The Traefik PVC is ReadWriteOnce; if an old pod still holds it, new pods stay in `Init` with a multi-attach warning. Delete the old Traefik pod (or the PVC if needed) so the new pod can mount `/data`.
