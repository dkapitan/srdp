set shell := ["bash", "-c"]
set dotenv-load := false

namespace := "srdp"

default: help

help:
	@just --list

# Local development
local-tls:
	mkdir -p kubernetes/certs
	mkcert -cert-file kubernetes/certs/selfsigned.crt -key-file kubernetes/certs/selfsigned.key "auth.local.dev" "marimo.local.dev" "quarto.local.dev"
	kubectl create namespace {{namespace}} --dry-run=client -o yaml | kubectl apply -f -
	kubectl create secret tls custom-ingress-cert --namespace {{namespace}} --key kubernetes/certs/selfsigned.key --cert kubernetes/certs/selfsigned.crt --dry-run=client -o yaml | kubectl apply -f -

local-deploy:
	cd kubernetes/srdp-chart && helm dependency update
	cd kubernetes/srdp-chart && helm upgrade --install srdp . --namespace {{namespace}} --create-namespace -f values.yaml -f values-secrets.yaml -f values-local.yaml

local-delete:
	helm uninstall srdp -n {{namespace}} || true
	kubectl delete pvc --all -n {{namespace}} || true

# Demo / infra
demo-apply:
	cd kubernetes/opentofu && source ../secrets.sh && tofu apply -auto-approve

demo-destroy:
	cd kubernetes/opentofu && source ../secrets.sh && tofu destroy -auto-approve

demo-kubeconfig:
	cd kubernetes/opentofu && tofu output -raw kubeconfig > kubeconfig.yaml && echo "export KUBECONFIG=$(pwd)/kubeconfig.yaml"

# Production-style Helm flows
prod-traefik-only:
	cd kubernetes && helm upgrade --install srdp srdp-chart --namespace {{namespace}} --create-namespace -f srdp-chart/values-prod.yaml --set zitadel.enabled=false --set oauth2-proxy.enabled=false --set marimo.enabled=false --set quarto.enabled=false

prod-auth-only:
	cd kubernetes && helm upgrade srdp srdp-chart --namespace {{namespace}} --reset-values -f srdp-chart/values-prod.yaml --set zitadel.enabled=true --set oauth2-proxy.enabled=true --set marimo.enabled=false --set quarto.enabled=false

prod-full:
	cd kubernetes && helm upgrade srdp srdp-chart --namespace {{namespace}} --reset-values -f srdp-chart/values-prod.yaml
