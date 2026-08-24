#!/bin/bash
# Send the same evaluation request to two PDPs and print the answers side by side.
#   PDP A: Keycloak (native implementation, has discovery)
#   PDP B: OPA + contrib authzen-proxy (via an adapter, no discovery)
#
# This is the hands-on check of "a PEP can swap PDPs without changes":
# the request JSON is written once, only the destination changes.

cd "$(dirname "$0")"
set -a && . ./.env && set +a

KC=http://localhost:8080
REALM=demo
PROXY=http://localhost:3030

# --- PDP A's endpoint comes from discovery
KC_EP=$(curl -s "$KC/realms/$REALM/.well-known/authzen-configuration" |
  python3 -c 'import sys,json;print(json.load(sys.stdin)["access_evaluation_endpoint"])' 2>/dev/null)

# --- PDP B has no discovery, so the spec path has to be assembled by hand
PROXY_EP="$PROXY/access/v1/evaluation"

KC_TOKEN=$(curl -s -d grant_type=client_credentials -d client_id=authzen-pdp \
  -d "client_secret=$KC_CLIENT_SECRET" \
  "$KC/realms/$REALM/protocol/openid-connect/token" |
  python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])' 2>/dev/null)

ask() { # url body [auth]
  local body_out code
  body_out=$(curl -s -w '\n%{http_code}' -X POST "$1" \
    -H 'Content-Type: application/json' \
    ${3:+-H "Authorization: Bearer $3"} \
    -d "$2")
  code=$(echo "$body_out" | tail -1)
  printf '%s (HTTP %s)' "$(echo "$body_out" | head -1)" "$code"
}

run() { # label json
  printf '%-46s\n' "$1"
  printf '  Keycloak : %s\n' "$(ask "$KC_EP" "$2" "$KC_TOKEN")"
  printf '  OPA+proxy: %s\n' "$(ask "$PROXY_EP" "$2")"
}

run "alice / can_read / document:123 (should permit)" \
  '{"subject":{"type":"user","id":"alice"},"action":{"name":"can_read"},"resource":{"type":"document","id":"123"}}'

run "bob / can_read / document:123 (should deny)" \
  '{"subject":{"type":"user","id":"bob"},"action":{"name":"can_read"},"resource":{"type":"document","id":"123"}}'

run "the spec example verbatim (alice@example.com)" \
  '{"subject":{"type":"user","id":"alice@example.com"},"action":{"name":"can_read"},"resource":{"type":"document","id":"123"}}'

run "undefined action (can_delete)" \
  '{"subject":{"type":"user","id":"alice"},"action":{"name":"can_delete"},"resource":{"type":"document","id":"123"}}'

run "nonexistent resource (999)" \
  '{"subject":{"type":"user","id":"alice"},"action":{"name":"can_read"},"resource":{"type":"document","id":"999"}}'

run "wrong resource.type (invoice)" \
  '{"subject":{"type":"user","id":"alice"},"action":{"name":"can_read"},"resource":{"type":"invoice","id":"123"}}'

run "subject.type omitted (REQUIRED by the spec)" \
  '{"subject":{"id":"alice"},"action":{"name":"can_read"},"resource":{"type":"document","id":"123"}}'

echo
echo "--- discovery"
printf '  Keycloak : %s\n' "$(curl -s -o /dev/null -w '%{http_code}' "$KC/realms/$REALM/.well-known/authzen-configuration")"
printf '  OPA+proxy: %s\n' "$(curl -s -o /dev/null -w '%{http_code}' "$PROXY/.well-known/authzen-configuration")"

echo "--- Evaluations (batch)"
BATCH='{"subject":{"type":"user","id":"alice"},"action":{"name":"can_read"},"resource":{"type":"document","id":"123"},"evaluations":[{},{"subject":{"type":"user","id":"bob"}}]}'
printf '  Keycloak : %s\n' "$(ask "$KC/realms/$REALM/authzen/access/v1/evaluations" "$BATCH" "$KC_TOKEN")"
printf '  OPA+proxy: %s\n' "$(ask "$PROXY/access/v1/evaluations" "$BATCH")"

echo "--- evaluation with no authentication"
printf '  Keycloak : %s\n' "$(ask "$KC_EP" '{"subject":{"type":"user","id":"alice"},"action":{"name":"can_read"},"resource":{"type":"document","id":"123"}}')"
printf '  OPA+proxy: %s\n' "$(ask "$PROXY_EP" '{"subject":{"type":"user","id":"alice"},"action":{"name":"can_read"},"resource":{"type":"document","id":"123"}}')"
