# Deployment guide

End-to-end bring-up of all environments, from empty Scaleway Projects to a
self-managing GitOps estate. Component detail lives in the linked READMEs; this
is the **ordered runbook**.

The philosophy: **hand-bootstrap the minimum to make the system self-managing,
then hand off to CI + GitOps.** Phases 0–5 are one-time; phase 6 flips the estate
to pull-based GitOps + gated CI (steady state).

## Cold-start dependencies (read first)

1. **Git remote** — Flux (installed by Terraform) reconciles from it; nothing
   deploys without it.
2. **Hub first** — spokes peer to the hub VPC. The Justfile reads `hub_vpc_id`
   from the hub state and injects it into spoke applies, so the **hub must apply
   before any spoke**.
3. **API ACL** — the Kapsule API is public but locked by `scaleway_k8s_acl`.
   First applies run from your IP; for ongoing access add the Headscale public
   IP (or operator egress) to `api_extra_allowed_cidrs`, or use the CI runner.

## Prerequisites

- `terraform` 1.10.3 (`.tool-versions`), `just`, `kubectl`, `helm`.
- A Scaleway Organization with **four Projects** (hub/dev/stage/prod) created.
- `SCW_DEFAULT_ORGANIZATION_ID` set (IAM apps/policies are Organization-scoped).
- An IAM API key (`SCW_ACCESS_KEY` / `SCW_SECRET_KEY`) with, across **all** Projects
  (+ the Organization for IAM): the **Editors** group **plus `ObjectStorageFullAccess`**
  (Editors doesn't grant S3 object access — needed by the state backend + lakehouse)
  **plus `IAMManager`** (Terraform creates the workload-identity IAM apps/keys;
  Editors doesn't include IAM management). Set the key's **preferred Project to hub**
  (see the state-backend note below).
- **Mesh control plane** uses an **sslip.io** name derived from the Headscale public
  IP by default (no domain to own; Caddy still gets a real Let's Encrypt cert). Set
  `headscale_fqdn` in `envs/hub/terraform.tfvars` only if you own a domain.
- **Verify your identity / raise quotas first.** Fresh Scaleway Organizations have
  per-instance-type quotas of **0** for several families — notably the
  memory-optimized **POP2** types this blueprint uses for the Kapsule compute pool
  (`POP2-8C-32G`). Kapsule node creation fails with
  `Quota exceeded on cp_servers_type_POP2_...` until you complete **identity
  verification** and/or request increases at
  <https://console.scaleway.com/organization/quotas>. Do this **before** applying
  the spokes. (Check `compute_node_type` in `envs/<env>/terraform.tfvars` against
  your available quota.)

## Phase 0 — Foundations (once)

1. **Create the git remote and push.** Set `git_repo_url` in
   `envs/*/terraform.tfvars` (+ `git_ssh_private_key` if private).
2. **Config:** `cp .env.example .env`, set `ORG_PREFIX` + the four Project IDs +
   region + SCW key.
3. **Fill env placeholders:** `runner_ssh_public_key` (spokes); the hub's
   `headscale_fqdn` / `headscale_ssh_public_key`.
4. **One-time chart customization:** set `REPLACE-PREFIX` in
   `deploy/srdp/base/values.yaml` and `helmrepository.yaml` to your `ORG_PREFIX`.
5. `just doctor`.

## Infrastructure (`just bootstrap-all`)

```bash
just bootstrap-all
```
Runs, in order (see [Justfile](../Justfile)):

| Step | Recipe | What |
|---|---|---|
| 1 | `bootstrap-state hub/dev/stage/prod` | per-Project S3 state buckets ([bootstrap](../deploy/bootstrap/README.md)) |
| 2 | `up hub` | VPC, egress gateway, Container Registry, Headscale |
| 3 | `up dev/stage/prod` | spokes: VPC peered to hub, Kapsule, RDB, Object Storage, Secret Manager, Flux, CI runner |

After the hub applies: point the `headscale_fqdn` A record at
`terraform -chdir=envs/hub output -raw headscale_public_ip`, and add that IP to
each spoke's `api_extra_allowed_cidrs`.

> **Cold-cluster note (Flux module).** The helm/kubernetes providers are
> configured from the Kapsule kubeconfig, which doesn't exist until the cluster
> is created. On a brand-new spoke, apply the cluster first, then the rest:
> `just _tf dev "apply -target=module.kapsule"` then `just up dev`.

## Phase 4 — Publish artifacts

Flux has nothing to pull until the chart + images are in the hub registry:

```bash
# from the srdp repo root (this blueprint lives at deploy/scaleway)
helm package deploy/kubernetes/srdp-chart
helm push srdp-chart-<ver>.tgz oci://rg.nl-ams.scw.cloud/<prefix>-srdp/helm
# + build & push srdp-etl / marimo / quarto images to the same registry
#   (see deploy/opentofu/scaleway/build-and-push.sh)
```
See [deploy/srdp](../deploy/srdp/README.md) for the version-pinning / promotion model.

## Phase 5 — Open the door (mesh)

Per cluster: seed the Headscale pre-auth key secret, approve routes on the VM,
then join from your laptop. Full steps in [deploy/mesh](../deploy/mesh/README.md).
After this, `kubectl` works over the mesh and you can reach internal services.

## Phase 6 — Hand off to self-management

- **Flux** reconciles `deploy/clusters/<env>` (SRDP + mesh + ESO/secrets).
- **Seed externally-originated secrets** into Secret Manager (oauth2 client
  id/secret from Zitadel, Headscale key) — ESO syncs them in.
- **GitHub Actions** manages infra: PR → plan, merge to main → gated apply
  hub → dev → stage → prod (see [.github/workflows](../.github/workflows/terraform-ci.yml)).

From here: **infra changes go through PR → workflow; app/version changes through
git commits → Flux.**

## Day-2

| Task | How |
|---|---|
| Change infra | PR → `terraform-ci` plan → merge → apply (stage/prod gated) |
| Upgrade SRDP in one env | bump chart version in `deploy/srdp/clusters/<env>`, commit |
| Promote | bump dev → soak → stage → prod, per env |
| Rotate generated secrets | `terraform apply` regenerates + re-stores in Secret Manager |
