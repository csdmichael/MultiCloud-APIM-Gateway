#!/usr/bin/env bash
# =============================================================================
# test-api.sh — Acquire JWT (Entra) and call APIM /worldcup/teams.
# -----------------------------------------------------------------------------
# Env vars:
#   APIM_HOST       e.g. apim-poc-my-dev.azure-api.net
#   API_PATH        default /worldcup/teams
#   TENANT_ID       Entra tenant id
#   AUDIENCE        e.g. api://apim-gateway
#   CLIENT_ID       App registration client id     (client_credentials)
#   CLIENT_SECRET   App registration client secret (client_credentials)
#   BURST           number of repeat calls (default 1) to trigger 429/403
# Usage:
#   APIM_HOST=apim-poc-my-dev.azure-api.net TENANT_ID=... AUDIENCE=... \
#   CLIENT_ID=... CLIENT_SECRET=... ./test-api.sh
# =============================================================================
set -euo pipefail

: "${APIM_HOST:?APIM_HOST required}"
: "${TENANT_ID:?TENANT_ID required}"
: "${AUDIENCE:?AUDIENCE required}"
API_PATH="${API_PATH:-/worldcup/teams}"
BURST="${BURST:-1}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${INTERACTIVE:-}" ]]; then
    TOKEN="$("$script_dir/get-token.sh" -i -t "$TENANT_ID" -a "$AUDIENCE")"
else
    : "${CLIENT_ID:?CLIENT_ID required (or set INTERACTIVE=1)}"
    : "${CLIENT_SECRET:?CLIENT_SECRET required (or set INTERACTIVE=1)}"
    TOKEN="$("$script_dir/get-token.sh" -t "$TENANT_ID" -a "$AUDIENCE" -c "$CLIENT_ID" -s "$CLIENT_SECRET")"
fi

if [[ -z "$TOKEN" ]]; then
    echo "Token acquisition failed" >&2; exit 1
fi

URL="https://${APIM_HOST}${API_PATH}"
echo "Calling $URL — burst=$BURST"

for n in $(seq 1 "$BURST"); do
    correlation="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"
    http_code=$(curl -sS -o /tmp/mcgw-body.$$ -D /tmp/mcgw-hdr.$$ -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "x-correlation-id: $correlation" \
        "$URL" || true)

    remaining=$(grep -i '^x-mcgw-user-tokens-remaining:' /tmp/mcgw-hdr.$$ | tr -d '\r' | awk -F': ' '{print $2}')
    echo "[$n] $http_code remaining-tokens=${remaining:-n/a}"

    if [[ "$n" -eq 1 ]]; then
        echo "---- Body ----"
        cat /tmp/mcgw-body.$$
        echo
        echo "---- Headers (x-mcgw-*, Retry-After, WWW-Authenticate) ----"
        grep -i -E '^(x-mcgw-|retry-after|www-authenticate):' /tmp/mcgw-hdr.$$ || true
    fi
done

rm -f /tmp/mcgw-body.$$ /tmp/mcgw-hdr.$$
