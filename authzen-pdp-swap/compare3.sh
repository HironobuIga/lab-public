#!/bin/bash
# Hit three PDPs with the same request.
#   A: Keycloak            native implementation
#   B: OPA + contrib proxy adapter, as shipped
#   C: OPA + hardened      adapter, with authentication / validation / discovery / batch added
#
# B and C look at the same OPA and the same Rego. Only the layer in front differs.

cd "$(dirname "$0")"
set -a && . ./.env && set +a

KC=http://localhost:8080
REALM=demo
B=http://localhost:3030
C=http://localhost:3031

KC_EP=$(curl -s "$KC/realms/$REALM/.well-known/authzen-configuration" |
  python3 -c 'import sys,json;print(json.load(sys.stdin)["access_evaluation_endpoint"])' 2>/dev/null)
TOK=$(curl -s -d grant_type=client_credentials -d client_id=authzen-pdp \
  -d "client_secret=$KC_CLIENT_SECRET" \
  "$KC/realms/$REALM/protocol/openid-connect/token" |
  python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])' 2>/dev/null)

ask() { # url body [token]
  local out code
  out=$(curl -s -m 10 -w '\n%{http_code}' -X POST "$1" -H 'Content-Type: application/json' \
    ${3:+-H "Authorization: Bearer $3"} -d "$2")
  code=$(printf '%s' "$out" | tail -1)
  printf '%s (%s)' "$(printf '%s' "$out" | head -1 | cut -c1-60)" "$code"
}

run() { # label json
  printf '%s\n' "$1"
  printf '  A Keycloak : %s\n' "$(ask "$KC_EP" "$2" "$TOK")"
  printf '  B contrib  : %s\n' "$(ask "$B/access/v1/evaluation" "$2" "$TOK")"
  printf '  C hardened : %s\n' "$(ask "$C/access/v1/evaluation" "$2" "$TOK")"
}

OK='{"subject":{"type":"user","id":"alice"},"action":{"name":"can_read"},"resource":{"type":"document","id":"123"}}'
NG='{"subject":{"type":"user","id":"bob"},"action":{"name":"can_read"},"resource":{"type":"document","id":"123"}}'
BAD='{"subject":{"id":"alice"},"action":{"name":"can_read"},"resource":{"type":"document","id":"123"}}'

run "should be permitted" "$OK"
run "should be denied" "$NG"
run "subject.type omitted (REQUIRED by the spec)" "$BAD"

echo
echo "no authentication, request that should be permitted"
printf '  A Keycloak : %s\n' "$(ask "$KC_EP" "$OK")"
printf '  B contrib  : %s\n' "$(ask "$B/access/v1/evaluation" "$OK")"
printf '  C hardened : %s\n' "$(ask "$C/access/v1/evaluation" "$OK")"

echo
echo "broken token, request that should be permitted"
printf '  A Keycloak : %s\n' "$(ask "$KC_EP" "$OK" "not-a-real-token")"
printf '  B contrib  : %s\n' "$(ask "$B/access/v1/evaluation" "$OK" "not-a-real-token")"
printf '  C hardened : %s\n' "$(ask "$C/access/v1/evaluation" "$OK" "not-a-real-token")"

echo
echo "discovery"
for n in A:$KC/realms/$REALM B:$B C:$C; do
  printf '  %s : %s\n' "${n%%:*}" \
    "$(curl -s -o /dev/null -m 10 -w '%{http_code}' "${n#*:}/.well-known/authzen-configuration")"
done

echo
echo "batch (alice and bob)"
BATCH='{"subject":{"type":"user","id":"alice"},"action":{"name":"can_read"},"resource":{"type":"document","id":"123"},"evaluations":[{},{"subject":{"type":"user","id":"bob"}}]}'
printf '  A Keycloak : %s\n' "$(ask "$KC/realms/$REALM/authzen/access/v1/evaluations" "$BATCH" "$TOK")"
printf '  B contrib  : %s\n' "$(ask "$B/access/v1/evaluations" "$BATCH" "$TOK")"
printf '  C hardened : %s\n' "$(ask "$C/access/v1/evaluations" "$BATCH" "$TOK")"
