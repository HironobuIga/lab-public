#!/bin/bash -e
# Send one evaluation request. The endpoint comes from discovery, never hardcoded.
# Usage: ./evaluate.sh '<evaluation request JSON>'

cd "$(dirname "$0")"
set -a && . ./.env && set +a

KC=http://localhost:8080
REALM=demo

EP=$(curl -s "$KC/realms/$REALM/.well-known/authzen-configuration" |
  python3 -c 'import sys,json;print(json.load(sys.stdin)["access_evaluation_endpoint"])')

TOKEN=$(curl -s -d grant_type=client_credentials -d client_id=authzen-pdp -d "client_secret=$KC_CLIENT_SECRET" \
  "$KC/realms/$REALM/protocol/openid-connect/token" |
  python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')

curl -s -w '\nHTTP %{http_code}\n' -X POST "$EP" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d "$1"
