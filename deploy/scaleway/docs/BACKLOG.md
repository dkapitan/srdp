# Backlog / known gaps

Tracked work before a full, hardened SRDP boot on Scaleway.

## Scaleway divergences from the Azure blueprint

- **L7 egress filtering.** Azure Firewall application rules (FQDN allow-lists)
  have no managed Scaleway equivalent. Current egress is Public Gateway NAT +
  L3/L4 VPC ACLs (`scaleway_vpc_acl`, not yet wired). If FQDN-level egress
  control is required, run a forward proxy (e.g. Squid/cilium egress gateway) in
  the cluster and force-route through it.
- **Keyless lakehouse access.** Scaleway has no pod OIDC workload identity, so
  DuckDB/dlt use a static IAM key (ESO-synced). Rotate it regularly
  (`terraform apply` re-mints) and scope the IAM policy to the lakehouse buckets
  only (currently `ObjectStorageFullAccess`).
- **Centralized egress through the hub.** Azure forced all spoke egress through
  the hub firewall (UDR). Here each spoke has its own Public Gateway. Routing all
  spoke egress through a single hub gateway over the VPC connector is possible
  with `scaleway_vpc_route` but not yet implemented.

## SRDP wiring

- **Secrets → chart `existingSecret` refs.** Verify the chart consumes
  `srdp-postgres`, `srdp-zitadel`, `srdp-oauth2`, `srdp-lakehouse` as existing
  secrets (the upstream `values-prod.example.yaml` inlines them). The chart may
  need `existingSecret` support added for Zitadel masterkey / DB password.
- **Internal Traefik LB.** Confirm `scw-loadbalancer-private: true` +
  `scw-loadbalancer-pn-ids` yields a PN-only LB and that Zitadel's
  `ExternalDomain` / oauth2-proxy redirect URIs resolve over the mesh.
- **DuckLake env contract.** Align the `srdp-etl` env vars
  (`DUCKLAKE_PG_*`, `LAKEHOUSE_S3_URL`, `AWS_*`) with `src/srdp/io/ducklake.py`
  and the S3 storage backend in `src/srdp/io/storage.py`.

## Mesh

- **Split-DNS** for resolving the app domain (and ideally the Kapsule API) by
  name over the mesh. Until wired, use the internal LB IP / `/etc/hosts`.
- **Durable authkey.** Store the Headscale pre-auth key in Secret Manager and
  sync via ESO instead of `kubectl create secret` by hand.

## Cross-Project peering (optional — not required)

- **The VPC connector is OFF by default (`enable_hub_peering = false`) and is not
  needed.** Unlike Azure (where spokes reached the hub ACR/Key Vault over private
  endpoints, requiring peering), Scaleway's hub services are public-endpoint +
  IAM: Container Registry (public + pull creds), Headscale (public), and Secret
  Manager is per-spoke. So no private hub↔spoke traffic exists to carry.
- A cross-Project `scaleway_vpc_connector` currently returns an opaque
  `invalid argument(s)` from the API (cross-Project may be unsupported, or need a
  manual accept). Only worth investigating if you later add a *private* shared
  service in the hub or centralize egress through a single hub gateway.
