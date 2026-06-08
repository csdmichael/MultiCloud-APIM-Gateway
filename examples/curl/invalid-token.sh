#!/usr/bin/env bash
# =============================================================================
# invalid-token.sh — Negative test: malformed/expired JWT.
# Expected outcome: HTTP 401 + { "error": "unauthorized", ... } envelope.
# -----------------------------------------------------------------------------
# Env vars needed: APIM_HOST
# =============================================================================
set -euo pipefail
: "${APIM_HOST:?APIM_HOST required}"

# Deliberately invalid token (3-segment, but signature is junk).
FAKE_TOKEN="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3MDAwMDAwMDAsImlzcyI6Imh0dHBzOi8vZmFrZS1pc3N1ZXIvIn0.invalidsignature"

curl -sS -i \
    -H "Authorization: Bearer $FAKE_TOKEN" \
    -H "x-correlation-id: $(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)" \
    "https://${APIM_HOST}/worldcup/teams"
