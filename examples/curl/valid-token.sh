#!/usr/bin/env bash
# =============================================================================
# valid-token.sh — Happy-path call: GET /worldcup/teams with a valid JWT.
# Expected outcome: HTTP 200 + World Cup JSON payload.
# -----------------------------------------------------------------------------
# Env vars needed:
#   APIM_HOST, TENANT_ID, AUDIENCE, CLIENT_ID, CLIENT_SECRET
# =============================================================================
set -euo pipefail

: "${APIM_HOST:?APIM_HOST required}"
: "${TENANT_ID:?TENANT_ID required}"
: "${AUDIENCE:?AUDIENCE required}"
: "${CLIENT_ID:?CLIENT_ID required}"
: "${CLIENT_SECRET:?CLIENT_SECRET required}"

TOKEN=$(curl -sS -X POST "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_id=${CLIENT_ID}" \
    --data-urlencode "client_secret=${CLIENT_SECRET}" \
    --data-urlencode "scope=${AUDIENCE}/.default" \
    | jq -r .access_token)

curl -sS -i \
    -H "Authorization: Bearer $TOKEN" \
    -H "x-correlation-id: $(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)" \
    "https://${APIM_HOST}/worldcup/teams"
