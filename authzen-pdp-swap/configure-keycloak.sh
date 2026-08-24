#!/bin/bash -e
# Build the demo realm so that the example from the AuthZEN spec
#   subject: alice@example.com / action: can_read / resource: document 123
# can be sent as-is.
#
# How AuthZEN maps onto the Keycloak authorization model:
#   action.name   -> authorization scope
#   resource.id   -> resource name
#   resource.type -> resource type
#   subject.id    -> username / UUID / email:<addr>
#   subject.type  -> "user" or "client"

cd "$(dirname "$0")"
set -a && . ./.env && set +a

KC=http://localhost:8080
REALM=demo

admin_token() {
  curl -s -d client_id=admin-cli \
    -d "username=$KC_BOOTSTRAP_ADMIN_USERNAME" \
    -d "password=$KC_BOOTSTRAP_ADMIN_PASSWORD" \
    -d grant_type=password \
    "$KC/realms/master/protocol/openid-connect/token" |
    python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])'
}

T=$(admin_token)
api() { # method path [body]
  local m=$1 p=$2 b=${3:-}
  if [ -n "$b" ]; then
    curl -s -w '\n%{http_code}' -X "$m" "$KC/admin$p" \
      -H "Authorization: Bearer $T" -H 'Content-Type: application/json' -d "$b"
  else
    curl -s -w '\n%{http_code}' -X "$m" "$KC/admin$p" -H "Authorization: Bearer $T"
  fi
}

say() { echo "--- $*"; }

say "realm $REALM"
api POST /realms "{\"realm\":\"$REALM\",\"enabled\":true}" | tail -1

say "role reader"
api POST "/realms/$REALM/roles" '{"name":"reader"}' | tail -1

say "user alice (reader, email alice@example.org)"
api POST "/realms/$REALM/users" \
  '{"username":"alice","enabled":true,"email":"alice@example.org","emailVerified":true}' | tail -1
say "user bob (no role)"
api POST "/realms/$REALM/users" \
  '{"username":"bob","enabled":true,"email":"bob@example.org","emailVerified":true}' | tail -1

ALICE=$(api GET "/realms/$REALM/users?username=alice&exact=true" | head -1 |
  python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["id"])')
ROLE=$(api GET "/realms/$REALM/roles/reader" | head -1 |
  python3 -c 'import sys,json;d=json.load(sys.stdin);print(json.dumps([{"id":d["id"],"name":d["name"]}]))')
say "grant reader to alice"
api POST "/realms/$REALM/users/$ALICE/role-mappings/realm" "$ROLE" | tail -1

say "client authzen-pdp (authorization services)"
api POST "/realms/$REALM/clients" "{
  \"clientId\":\"authzen-pdp\",\"enabled\":true,\"secret\":\"$KC_CLIENT_SECRET\",
  \"serviceAccountsEnabled\":true,\"directAccessGrantsEnabled\":false,
  \"publicClient\":false,\"authorizationServicesEnabled\":true
}" | tail -1

CID=$(api GET "/realms/$REALM/clients?clientId=authzen-pdp" | head -1 |
  python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["id"])')
RS="/realms/$REALM/clients/$CID/authz/resource-server"

# Add an audience mapper for the side that verifies tokens by introspection
# (hardened-proxy). By default the token's aud is just "account", and Keycloak
# requires the introspecting client to appear in the token audience.
# Without this, introspection returns {"active":false} for a perfectly valid token.
say "audience mapper (for introspection)"
api POST "/realms/$REALM/clients/$CID/protocol-mappers/models" '{
  "name":"authzen-pdp-audience","protocol":"openid-connect",
  "protocolMapper":"oidc-audience-mapper",
  "config":{"included.client.audience":"authzen-pdp","access.token.claim":"true"}
}' | tail -1

say "scope can_read"
api POST "$RS/scope" '{"name":"can_read"}' | tail -1

say "resource 123 (type document)"
api POST "$RS/resource" '{
  "name":"123","type":"document","scopes":[{"name":"can_read"}]
}' | tail -1

say "policy reader-policy"
api POST "$RS/policy/role" '{
  "name":"reader-policy","roles":[{"id":"reader"}]
}' | tail -1

say "permission read-document-permission"
api POST "$RS/permission/scope" '{
  "name":"read-document-permission","decisionStrategy":"AFFIRMATIVE",
  "resources":["123"],"scopes":["can_read"],"policies":["reader-policy"]
}' | tail -1

echo
echo "done. realm=$REALM users=alice(reader),bob(none) resource=123(document) scope=can_read"
