#!/bin/bash -e
# The response-side `context` carries no reason for a decision (only a reason for
# stopping, and only under deny_on_first_deny). So does the request-side
# context / properties reach the policy at all?
#
# The Keycloak guide says resource.properties and the top-level context are merged
# into the evaluation context, and subject.properties into the subject's identity
# attributes. Add a Regex policy (which matches an identity attribute against a
# pattern) and see whether it really takes effect.

cd "$(dirname "$0")"
set -a && . ./.env && set +a

KC=http://localhost:8080
REALM=demo

T=$(curl -s -d client_id=admin-cli -d "username=$KC_BOOTSTRAP_ADMIN_USERNAME" \
  -d "password=$KC_BOOTSTRAP_ADMIN_PASSWORD" -d grant_type=password \
  "$KC/realms/master/protocol/openid-connect/token" |
  python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')

api() {
  local m=$1 p=$2 b=${3:-}
  if [ -n "$b" ]; then
    curl -s -w '\n%{http_code}' -X "$m" "$KC/admin$p" -H "Authorization: Bearer $T" \
      -H 'Content-Type: application/json' -d "$b"
  else
    curl -s -w '\n%{http_code}' -X "$m" "$KC/admin$p" -H "Authorization: Bearer $T"
  fi
}

CID=$(api GET "/realms/$REALM/clients?clientId=authzen-pdp" | head -1 |
  python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["id"])')
RS="/realms/$REALM/clients/$CID/authz/resource-server"

echo "--- scope can_export"
api POST "$RS/scope" '{"name":"can_export"}' | tail -1

echo "--- add can_export to resource 123"
RES=$(api GET "$RS/resource?name=123" | head -1 |
  python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["_id"])')
api PUT "$RS/resource/$RES" '{
  "name":"123","type":"document",
  "scopes":[{"name":"can_read"},{"name":"can_export"}]
}' | tail -1

echo "--- regex policy: identity attribute department is finance"
api POST "$RS/policy/regex" '{
  "name":"finance-dept-policy","targetClaim":"department","pattern":"^finance$"
}' | tail -1

echo "--- permission: can_export only for the finance department"
api POST "$RS/permission/scope" '{
  "name":"export-document-permission","decisionStrategy":"UNANIMOUS",
  "resources":["123"],"scopes":["can_export"],"policies":["finance-dept-policy"]
}' | tail -1

echo
echo "=== ask for can_export while varying subject.properties.department"
req() { # department (empty means no properties at all)
  if [ -n "$1" ]; then
    printf '{"subject":{"type":"user","id":"alice","properties":{"department":"%s"}},"action":{"name":"can_export"},"resource":{"type":"document","id":"123"}}' "$1"
  else
    printf '{"subject":{"type":"user","id":"alice"},"action":{"name":"can_export"},"resource":{"type":"document","id":"123"}}'
  fi
}
for dept in finance sales; do
  printf '  department=%-8s -> %s\n' "$dept" "$(./evaluate.sh "$(req "$dept")" | head -1)"
done
printf '  no properties       -> %s\n' "$(./evaluate.sh "$(req '')" | head -1)"
printf '  (control) can_read  -> %s\n' \
  "$(./evaluate.sh '{"subject":{"type":"user","id":"alice"},"action":{"name":"can_read"},"resource":{"type":"document","id":"123"}}' | head -1)"

echo
echo "=== X-Request-ID propagation (tracing recommended by the spec)"
EP=$(curl -s "$KC/realms/$REALM/.well-known/authzen-configuration" |
  python3 -c 'import sys,json;print(json.load(sys.stdin)["access_evaluation_endpoint"])')
TOK=$(curl -s -d grant_type=client_credentials -d client_id=authzen-pdp \
  -d "client_secret=$KC_CLIENT_SECRET" \
  "$KC/realms/$REALM/protocol/openid-connect/token" |
  python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
printf '  Keycloak : %s\n' "$(curl -s -D- -o /dev/null -X POST "$EP" \
  -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -H 'X-Request-ID: probe-123' \
  -d '{"subject":{"type":"user","id":"alice"},"action":{"name":"can_read"},"resource":{"type":"document","id":"123"}}' |
  grep -i '^x-request-id' | tr -d '\r' || echo '(not returned)')"
printf '  OPA+proxy: %s\n' "$(curl -s -D- -o /dev/null -X POST http://localhost:3030/access/v1/evaluation \
  -H 'Content-Type: application/json' -H 'X-Request-ID: probe-123' \
  -d '{"subject":{"type":"user","id":"alice"},"action":{"name":"can_read"},"resource":{"type":"document","id":"123"}}' |
  grep -i '^x-request-id' | tr -d '\r' || echo '(not returned)')"
