# GitOps tree — what clusters reconcile (Flux)

Shared, cloud-agnostic Flux tree. Each cluster's Flux (installed by the cloud
blueprint's Terraform) reconciles exactly **one leaf**:

```
deploy/gitops/
  platform/
    base/                    # cloud-agnostic platform controllers (External Secrets)
  clusters/
    <cloud>/<env>/           # ONE leaf per cluster — the Flux entry point
      kustomization.yaml     #   pulls in platform/base + the cloud/env bindings
      clustersecretstore.yaml#   cloud-specific: how ESO reaches the secret store
      externalsecrets.yaml   #   env-specific: which secrets sync into the cluster
```

Flux path per cluster: `deploy/gitops/clusters/<cloud>/<env>` (set by the
blueprint's `flux` module — see `deploy/scaleway/modules/flux`).

## Design rules

- **`platform/base` stays cloud-agnostic.** Anything that needs a provider,
  region, project id, or credential goes in the cluster leaf.
- **One leaf = one cluster = one Flux Kustomization.** No leaf references
  another leaf; envs upgrade independently by construction.
- **Secrets are referenced, never inlined.** The leaves map External Secrets
  from the cloud's secret manager; the store credentials are seeded by
  Terraform (see the blueprint).

## Adding an environment

Copy an existing leaf (e.g. `clusters/scaleway/dev` → `clusters/scaleway/qa`),
replace the env name in the `remoteRef` keys and the ClusterSecretStore
project id, and point the new cluster's Flux at the new path.

## Adding a cloud

Create `clusters/<cloud>/<env>/` leaves with that cloud's ClusterSecretStore
(ESO supports most providers) and reuse `platform/base` unchanged.

The SRDP application itself (HelmRelease + values) is **not here yet** — it
lands as a sibling of `platform/` via the shared multi-cloud deployment layer
(issue #38).
