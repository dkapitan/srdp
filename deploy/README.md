# SRDP deploy — quickstart

## Local (kind)

**Vooraf (eenmalig):** `mkcert -install`; voeg aan `/etc/hosts` toe:
`127.0.0.1 dagster.local.dev marimo.local.dev quarto.local.dev auth.local.dev`

```bash
open -a Docker                                   # wacht tot de daemon draait
kind create cluster --name srdp                  # Apple Silicon + DOCKER_DEFAULT_PLATFORM=amd64? prefix met DOCKER_DEFAULT_PLATFORM=linux/arm64
# images 1e keer bouwen (docker build ... srdp-etl/marimo/quarto:v1.0), daarna elke verse cluster laden:
for i in srdp-etl marimo quarto; do kind load docker-image rg.nl-ams.scw.cloud/srdp-registry/$i:v1.0 --name srdp; done
just local-tls                                   # mkcert-cert + custom-ingress-cert secret
just local-deploy                                # volledige stack
kubectl get pods -n srdp -w                      # wacht tot alles 1/1 / Completed
deploy/kubernetes/provision-oidc.sh              # Zitadel OIDC-app (DOMAIN default local.dev)
sudo kubectl port-forward -n srdp svc/srdp-traefik 443:443 80:80   # laten draaien
```
**Test:** `https://dagster.local.dev` (+ marimo./quarto./auth.) — mkcert-TLS, login via Zitadel.
**Afbreken:** `just local-delete` (licht) of `kind delete cluster --name srdp` (volledig).

## Cloud (Scaleway)

**Vooraf (eenmalig):**
1. Registry `srdp-registry` bestaat in Scaleway Console (regio `nl-ams`).
2. `cp deploy/opentofu/scaleway/secrets.sh{.example,}` en vul project-ID + API-key (IAM → API keys).
3. `cp deploy/kubernetes/srdp-chart/values-prod{.example,}.yaml` en vul de secrets. (Beide gitignored.)

**Deploy:**
```bash
source deploy/opentofu/scaleway/secrets.sh
just build-and-push                              # images (amd64) → registry
(cd deploy/opentofu/scaleway && tofu init)       # alleen 1e keer
just prod-apply                                  # OpenTofu: cluster + netwerk
just prod-use-kubeconfig
just prod-traefik-only && just prod-get-values   # → LB-IP
sed -i '' 's|LOAD_BALANCER_IP|<IP>|g' deploy/kubernetes/srdp-chart/values-prod.yaml
just prod-full                                   # volledige stack
KUBECONFIG=deploy/opentofu/scaleway/kubeconfig.yaml DOMAIN=<IP>.nip.io \
  deploy/kubernetes/provision-oidc.sh            # Zitadel OIDC-app + oauth2-proxy koppelen
```

**Na provisionen:** zet de creds vast in `values-prod.yaml` zodat een volgende `just prod-full`
niet botst met de kubectl-patch (SSA-conflict):
```bash
export KUBECONFIG=deploy/opentofu/scaleway/kubeconfig.yaml
kubectl get secret srdp-oauth2-proxy -n srdp -o jsonpath='{.data.client-id}'     | base64 -d   # → clientID
kubectl get secret srdp-oauth2-proxy -n srdp -o jsonpath='{.data.client-secret}' | base64 -d   # → clientSecret
# plak beide in values-prod.yaml (oauth2-proxy.config.clientID / clientSecret)
```

**Test:** `https://dagster.<IP>.nip.io` (+ marimo./quarto./auth.) — vertrouwde Let's Encrypt-TLS.

**Afbreken (stopt kosten):**
```bash
source deploy/opentofu/scaleway/secrets.sh
just prod-destroy
```

**Verschil met lokaal:** cluster via OpenTofu i.p.v. kind · images via registry i.p.v. `kind load` (amd64!) ·
Let's Encrypt i.p.v. mkcert · publiek LB-IP i.p.v. port-forward. Concepten (chart, subcharts, OIDC) identiek.
