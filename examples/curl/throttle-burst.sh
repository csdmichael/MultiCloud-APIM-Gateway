#!/usr/bin/env bash
# =============================================================================
# throttle-burst.sh — Drives token-per-minute / per-hour exhaustion.
# Expected outcome: First N calls return 200, then 429 (rate limit) once
# the per-minute bucket empties, then 403 (quota) when the per-hour quota
# is exhausted.
# -----------------------------------------------------------------------------
# Env vars needed: APIM_HOST, TENANT_ID, AUDIENCE, CLIENT_ID, CLIENT_SECRET
#                  COUNT       default 80
#                  CONCURRENCY default 8
# =============================================================================
set -euo pipefail

: "${APIM_HOST:?APIM_HOST required}"
: "${TENANT_ID:?TENANT_ID required}"
: "${AUDIENCE:?AUDIENCE required}"
: "${CLIENT_ID:?CLIENT_ID required}"
: "${CLIENT_SECRET:?CLIENT_SECRET required}"

COUNT="${COUNT:-80}"
CONCURRENCY="${CONCURRENCY:-8}"

TOKEN=$(curl -sS -X POST "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_id=${CLIENT_ID}" \
    --data-urlencode "client_secret=${CLIENT_SECRET}" \
    --data-urlencode "scope=${AUDIENCE}/.default" \
    | jq -r .access_token)

URL="https://${APIM_HOST}/worldcup/teams"

call_one() {
    local n=$1
    local hdr_file
    hdr_file=$(mktemp)
    local code
    code=$(curl -sS -o /dev/null -D "$hdr_file" -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "x-correlation-id: $(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)" \
        "$URL" || echo "000")
    local remaining
    remaining=$(grep -i '^x-mcgw-user-tokens-remaining:' "$hdr_file" | tr -d '\r' | awk -F': ' '{print $2}')
    local retry
    retry=$(grep -i '^retry-after:' "$hdr_file" | tr -d '\r' | awk -F': ' '{print $2}')
    printf "[%03d] http=%s remaining=%s retry-after=%s\n" "$n" "$code" "${remaining:-n/a}" "${retry:-n/a}"
    rm -f "$hdr_file"
}

export -f call_one
export TOKEN URL

if command -v xargs >/dev/null 2>&1; then
    seq 1 "$COUNT" | xargs -I{} -P "$CONCURRENCY" bash -c 'call_one "$@"' _ {}
else
    for n in $(seq 1 "$COUNT"); do call_one "$n"; done
fi
