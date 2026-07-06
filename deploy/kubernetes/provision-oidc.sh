#!/usr/bin/env bash
# Idempotent Zitadel OIDC provisioning for the local SRDP stack.
# Run AFTER `just local-deploy` (oauth2-proxy may CrashLoop until this runs).
#   deploy/kubernetes/provision-oidc.sh   (run from anywhere; uses current kube context)
# Solves the chicken-egg: a fresh Zitadel generates a new clientId, so oauth2-proxy's
# hardcoded creds never match. This creates/reuses the app and patches the live secret.
set -euo pipefail

NS=srdp
DOMAIN="${DOMAIN:-local.dev}"          # override for cloud, e.g. DOMAIN=51.15.x.x.nip.io
ZHOST="auth.$DOMAIN"
PROJNAME=SRDP
APPNAME=oauth2-proxy
OAUTH_SECRET=srdp-oauth2-proxy
REDIRECTS="[\"https://dagster.$DOMAIN/oauth2/callback\",\"https://marimo.$DOMAIN/oauth2/callback\",\"https://quarto.$DOMAIN/oauth2/callback\"]"

PAT=$(kubectl get secret iam-admin-pat -n "$NS" -o jsonpath='{.data.pat}' | base64 -d)

kubectl port-forward -n "$NS" svc/srdp-zitadel 8080:8080 >/tmp/zt-pf.log 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT
echo -n "waiting for Zitadel API"
for _ in $(seq 1 30); do
  curl -sf -H "Host: $ZHOST" http://localhost:8080/.well-known/openid-configuration >/dev/null 2>&1 && break
  echo -n "."; sleep 1
done; echo

api() { curl -s -H "Authorization: Bearer $PAT" -H "Host: $ZHOST" -H "Content-Type: application/json" "$@"; }
B=http://localhost:8080/management/v1
jq_get() { python3 -c "import sys,json;d=json.load(sys.stdin);print($1)"; }
b64() { printf %s "$1" | base64 | tr -d '\n'; }   # tr: avoid macOS 76-col wrapping

# 1. find-or-create project
PID=$(api -X POST "$B/projects/_search" -d '{"queries":[{"nameQuery":{"name":"'"$PROJNAME"'","method":"TEXT_QUERY_METHOD_EQUALS"}}]}' \
  | jq_get "(d.get('result') or [{}])[0].get('id','')")
if [ -z "$PID" ]; then
  PID=$(api -X POST "$B/projects" -d '{"name":"'"$PROJNAME"'"}' | jq_get "d['id']")
  echo "created project $PID"
else echo "found project $PID"; fi

# 2. find-or-create app
AID=$(api -X POST "$B/projects/$PID/apps/_search" -d '{"queries":[{"nameQuery":{"name":"'"$APPNAME"'","method":"TEXT_QUERY_METHOD_EQUALS"}}]}' \
  | jq_get "(d.get('result') or [{}])[0].get('id','')")
if [ -z "$AID" ]; then
  RESP=$(api -X POST "$B/projects/$PID/apps/oidc" -d '{"name":"'"$APPNAME"'","redirectUris":'"$REDIRECTS"',"postLogoutRedirectUris":["https://dagster.'"$DOMAIN"'/"],"responseTypes":["OIDC_RESPONSE_TYPE_CODE"],"grantTypes":["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"],"appType":"OIDC_APP_TYPE_WEB","authMethodType":"OIDC_AUTH_METHOD_TYPE_BASIC","devMode":true}')
  CID=$(echo "$RESP" | jq_get "d['clientId']"); CSECRET=$(echo "$RESP" | jq_get "d['clientSecret']")
  echo "created app, clientId=$CID"
else
  CID=$(api "$B/projects/$PID/apps/$AID" | jq_get "d['app']['oidcConfig']['clientId']")
  CSECRET=$(api -X POST "$B/projects/$PID/apps/$AID/oidc_config/_generate_client_secret" | jq_get "d['clientSecret']")
  echo "reused app $AID, regenerated secret, clientId=$CID"
fi

# 3. patch oauth2-proxy and restart
kubectl patch secret "$OAUTH_SECRET" -n "$NS" --type merge \
  -p "{\"data\":{\"client-id\":\"$(b64 "$CID")\",\"client-secret\":\"$(b64 "$CSECRET")\"}}" >/dev/null
kubectl rollout restart deploy/srdp-oauth2-proxy -n "$NS" >/dev/null
echo "patched $OAUTH_SECRET + restarted oauth2-proxy. Done."
