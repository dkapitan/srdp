# SRDP on Scaleway — deployment bridge (Flux GitOps)

Connects the Terraform landing zone to the cloud-agnostic `srdp-chart`.
**The chart stays cloud-agnostic; every Scaleway specific lives here.**

## Independent per-env deploy & upgrade — by construction

Each env runs **its own Flux controller in its own Kapsule cluster/Project**,
reconciling **only its own path**:

```
deploy/srdp/
  base/                 # shared: namespace, HelmRepository (registry), HelmRelease, base values
  clusters/
    dev/    -> dev's Flux reconciles this only
    stage/  -> stage's Flux reconciles this only
    prod/   -> prod's Flux reconciles this only
```

There is **no deployer that spans Projects**. Each overlay pins its **own chart
version**, so upgrades are independent — bumping dev reconciles dev and nothing
else.

### Layout mechanics
- `base/` holds the `HelmRelease` (version `0.0.0`, replaced per overlay), the
  OCI `HelmRepository` (hub Container Registry), and `base/values.yaml` →
  `srdp-values-base`.
- Each `clusters/<env>/` adds `values.yaml` → `srdp-values-env` (overrides base)
  and a patch setting the pinned chart version.
- `HelmRelease.valuesFrom` merges base then env.

## Flux install — managed by Terraform (not `flux bootstrap`)

Scaleway has no native GitOps extension (Azure had `microsoft.flux`), so
`modules/flux` installs Flux with the community Helm charts (`flux2` controllers
+ `flux2-sync` GitRepository/Kustomization), wired into each `envs/<env>` and
pinned to `deploy/clusters/<env>`. So `terraform apply` per env both builds the
cluster and points its Flux at the right path.

Private-repo auth: set `git_repo_url` to an `ssh://` URL and supply
`git_ssh_private_key` (the flux2-sync chart creates the deploy-key secret).

## Registry auth — static credentials (NOT keyless)

Unlike Azure (`provider: azure` + kubelet managed identity), Scaleway registries
use credentials. A `registry-pull` IAM key (ContainerRegistryReadOnly on the hub
Project) is stored in Secret Manager and synced by ESO into the `srdp-registry`
secret — used both as the Flux `HelmRepository.secretRef` and the chart
`imagePullSecrets`.

## One-time blueprint customization

`base/values.yaml` and `base/helmrepository.yaml` contain `REPLACE-PREFIX` and a
region (`nl-ams`) in the registry URLs. Set them once to your `ORG_PREFIX` /
region:

```bash
grep -rl REPLACE-PREFIX deploy/srdp | xargs sed -i '' 's/REPLACE-PREFIX/acme/g'
```

## Promotion flow
```
1. build + push srdp-chart vX.Y.Z to oci://rg.nl-ams.scw.cloud/<prefix>-srdp/helm
2. clusters/dev   version = vX.Y.Z -> commit -> dev Flux reconciles -> soak
3. clusters/stage version = vX.Y.Z -> commit -> stage -> soak
4. clusters/prod  version = vX.Y.Z -> commit -> prod
```
Image tags promote the same way, per env, in `clusters/<env>/values.yaml`.

## Terraform output -> value mapping

| Value (in clusters/<env>/values.yaml) | Source |
|---|---|
| `…Postgres.Host`, `dagster…postgresqlHost`, `DUCKLAKE_PG_HOST` | env `postgres_host` |
| `traefik…scw-loadbalancer-pn-ids` | env `networking.private_network_id` |
| `LAKEHOUSE_S3_URL` | env `lakehouse_s3_url` |
| image `repository` (base/values.yaml) | hub `registry_endpoint` |
| ClusterSecretStore `projectId` | env `project_id` |

## Lakehouse auth at runtime (S3 keys — Scaleway has no pod identity)

Object storage isn't in Helm — it's used inside the `srdp-etl`/marimo images.
Data pods read `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` from the
`srdp-lakehouse` secret (ESO-synced from a `data` IAM key with
ObjectStorageFullAccess). DuckDB (`httpfs`) and dlt (`s3fs`) then talk to
`https://s3.<region>.scw.cloud`. This is the main divergence from Azure, which
used keyless workload identity.

## Secrets

Postgres password, Zitadel masterkey, oauth2 client/cookie secrets, lakehouse S3
keys, registry pull keys → Secret Manager, synced via External Secrets,
referenced as existing secrets. Never inline in `values`.
