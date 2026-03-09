set shell := ["bash", "-c"]
set dotenv-load := false

namespace := "srdp"
kubeconfig := justfile_directory() + "/kubernetes/opentofu/kubeconfig.yaml"

default: help

help:
	@just --list

# Local development
local-tls:
	mkdir -p kubernetes/certs
	mkcert -cert-file kubernetes/certs/selfsigned.crt -key-file kubernetes/certs/selfsigned.key "auth.local.dev" "marimo.local.dev" "quarto.local.dev" "dagster.local.dev"
	kubectl create namespace {{namespace}} --dry-run=client -o yaml | kubectl apply -f -
	kubectl create secret tls custom-ingress-cert --namespace {{namespace}} --key kubernetes/certs/selfsigned.key --cert kubernetes/certs/selfsigned.crt --dry-run=client -o yaml | kubectl apply -f -

local-deploy:
	cd kubernetes/srdp-chart && helm dependency update
	cd kubernetes/srdp-chart && helm upgrade --install srdp . --namespace {{namespace}} --create-namespace -f values.yaml -f values-local.yaml

local-delete:
	helm uninstall srdp -n {{namespace}} || true
	kubectl delete pvc --all -n {{namespace}} || true

# Prod / infra
prod-apply:
	cd kubernetes/opentofu && source ./secrets.sh && tofu apply -auto-approve

prod-destroy:
	cd kubernetes/opentofu && source ./secrets.sh && tofu destroy -auto-approve

prod-use-kubeconfig:
	cd kubernetes/opentofu && tofu output -raw kubeconfig > "{{kubeconfig}}" && echo "kubeconfig written to {{kubeconfig}}"

prod-get-values:
	@echo "Fetching dynamic values..."
	@if [ ! -f "{{kubeconfig}}" ]; then echo "kubeconfig not found, run 'just prod-use-kubeconfig' first"; exit 1; fi
	@KUBECONFIG="{{kubeconfig}}" kubectl get svc srdp-traefik -n {{namespace}} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' | xargs -I{} printf "LOAD_BALANCER_IP:\t%s\n" "{}"

prod-traefik-only:
	cd kubernetes && \
		if [ ! -f "{{kubeconfig}}" ]; then echo "kubeconfig not found, run 'just prod-use-kubeconfig' first"; exit 1; fi; \
		export KUBECONFIG="{{kubeconfig}}"; \
		helm upgrade --install srdp srdp-chart --namespace {{namespace}} --create-namespace -f srdp-chart/values-prod.yaml --set zitadel.enabled=false --set oauth2-proxy.enabled=false --set dagster.enabled=false --set marimo.enabled=false --set quarto.enabled=false

prod-auth-only:
	cd kubernetes && \
		if [ ! -f "{{kubeconfig}}" ]; then echo "kubeconfig not found, run 'just prod-use-kubeconfig' first"; exit 1; fi; \
		export KUBECONFIG="{{kubeconfig}}"; \
		helm upgrade srdp srdp-chart --namespace {{namespace}} --reset-values -f srdp-chart/values-prod.yaml --set zitadel.enabled=true --set oauth2-proxy.enabled=true --set dagster.enabled=false --set marimo.enabled=false --set quarto.enabled=false

prod-full:
	cd kubernetes && \
		if [ ! -f "{{kubeconfig}}" ]; then echo "kubeconfig not found, run 'just prod-use-kubeconfig' first"; exit 1; fi; \
		export KUBECONFIG="{{kubeconfig}}"; \
		helm upgrade srdp srdp-chart --namespace {{namespace}} --reset-values -f srdp-chart/values-prod.yaml

prod-uninstall:
	cd kubernetes && \
		if [ ! -f "{{kubeconfig}}" ]; then echo "kubeconfig not found, run 'just prod-use-kubeconfig' first"; exit 1; fi; \
		export KUBECONFIG="{{kubeconfig}}"; \
		kubectl delete jobs --all -n {{namespace}} && \
		kubectl delete pvc --all -n {{namespace}} && \
		helm uninstall srdp -n {{namespace}} || true
