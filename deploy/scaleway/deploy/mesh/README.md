# Mesh — operator access to the private estate (Headscale + VM subnet routers)

Reach the private estate (RDB, the internal Traefik LB, **and the Kapsule API**)
over a Headscale/Tailscale mesh — without exposing anything publicly and without
pinning your roaming laptop IP in the API ACL.

## Architecture (all Terraform-provisioned — no k8s subnet-router pod)

```
laptop (tailscale) ─┐
                    ▼
        Headscale control plane              (hub Instance, public, modules/headscale-vm)
        https://mesh.<your-domain>
                    ▲          ▲
        ┌───────────┘          └───────────┐
   mesh-router VM            mesh-router VM            (modules/mesh-router, one per spoke)
   in stage PN               in prod PN
   advertises:               advertises:
     10.30.0.0/16  (PN)        10.20.0.0/16  (PN)
     <stage API>/32            <prod API>/32
```

Why a **VM**, not a Flux pod (the design changed deliberately):

- **No cold-start.** The router is up the moment `terraform apply` finishes — it
  does not depend on the cluster being reachable (a k8s subnet-router pod can't
  help you reach the API that schedules it).
- **Break-glass.** It survives a broken cluster.
- **Reaches the API.** Kapsule's control plane is a *public, ACL'd* endpoint
  ([no private API on Kapsule](https://github.com/scaleway/docs-content/blob/main/pages/kubernetes/reference-content/secure-cluster-with-private-network.mdx)).
  The router advertises the API's `/32` and forwards that traffic out through the
  spoke **Public Gateway**, whose IP is allow-listed in `scaleway_k8s_acl`. So
  kubectl works over the mesh, sourced from the stable gateway IP — your laptop IP
  never needs to be in the ACL.

Worker nodes run with **full isolation** (`public_ip_disabled = true`): no public
IPs, all egress (including kubelet → public control plane) via the Public Gateway.

## One-time setup

1. **Terraform apply hub** → Headscale Instance up. Point your `headscale_fqdn`
   A record at `terraform -chdir=envs/hub output -raw headscale_public_ip`, and
   make sure TLS resolves (Caddy ACME needs the real domain).
2. **Create a user + pre-auth key** on the Headscale VM:
   ```bash
   headscale users create platform
   headscale preauthkeys create -u platform --reusable --expiration 90d
   ```
3. **Give the mesh-routers the key**: set `headscale_url` + `headscale_authkey`
   in `envs/<spoke>/terraform.tfvars` and re-apply (or run
   `TS_AUTHKEY=<key> /usr/local/bin/mesh-up.sh` on the VM). It registers and
   advertises `PN CIDR + API /32`.
4. **Approve the routes** on the Headscale VM:
   ```bash
   headscale routes list
   headscale routes enable -r <id>     # PN CIDR and API /32 for each spoke
   ```
5. **Join from your laptop**:
   ```bash
   tailscale up --login-server=https://mesh.<your-domain> --accept-routes
   kubectl get nodes      # API reached over the mesh, via the gateway IP
   ```

## Bootstrap note (first Flux install)

Until the mesh is live (real Headscale FQDN + key), Terraform's phase-2 apply
(installing Flux from your workstation) still needs API access. Either add your
operator IP to `api_extra_allowed_cidrs` temporarily, or run the apply from an
in-PN host. Remove the operator IP once the mesh + gateway-IP allow-listing work.
