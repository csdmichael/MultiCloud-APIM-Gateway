#!/usr/bin/env bash
# =============================================================================
# get-token.sh — Acquire a Microsoft Entra ID JWT for the APIM gateway.
# -----------------------------------------------------------------------------
# Modes:
#   client_credentials (default) - requires CLIENT_ID + CLIENT_SECRET
#   interactive (-i)             - uses `az account get-access-token`
#
# Required env / flags:
#   TENANT_ID         (or -t)   Entra tenant id
#   AUDIENCE          (or -a)   Token audience (e.g. api://apim-gateway)
#   CLIENT_ID         (or -c)   App registration client id (client_credentials only)
#   CLIENT_SECRET     (or -s)   App registration secret    (client_credentials only)
#
# Emits the JWT to STDOUT only, so callers can capture:
#   TOKEN=$(./get-token.sh -t $TENANT -a api://apim-gateway -c $CID -s $SECRET)
# =============================================================================
set -euo pipefail

usage() {
    sed -n '2,18p' "$0"
    exit 1
}

INTERACTIVE=0
while getopts ":t:a:c:s:ih" opt; do
    case "$opt" in
        t) TENANT_ID="$OPTARG" ;;
        a) AUDIENCE="$OPTARG" ;;
        c) CLIENT_ID="$OPTARG" ;;
        s) CLIENT_SECRET="$OPTARG" ;;
        i) INTERACTIVE=1 ;;
        h) usage ;;
        *) usage ;;
    esac
done

: "${TENANT_ID:?TENANT_ID required (env or -t)}"
: "${AUDIENCE:?AUDIENCE required  (env or -a)}"

if [[ "$INTERACTIVE" == "1" ]]; then
    if ! az account show >/dev/null 2>&1; then
        echo "Logging in interactively (device code)..." >&2
        az login --tenant "$TENANT_ID" --allow-no-subscriptions --use-device-code >/dev/null
    fi
    az account get-access-token --tenant "$TENANT_ID" --resource "$AUDIENCE" --query accessToken -o tsv
    exit 0
fi

: "${CLIENT_ID:?CLIENT_ID required for client_credentials (env or -c)}"
: "${CLIENT_SECRET:?CLIENT_SECRET required for client_credentials (env or -s)}"

curl -sS -X POST "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_id=${CLIENT_ID}" \
    --data-urlencode "client_secret=${CLIENT_SECRET}" \
    --data-urlencode "scope=${AUDIENCE}/.default" \
    | jq -r .access_token
