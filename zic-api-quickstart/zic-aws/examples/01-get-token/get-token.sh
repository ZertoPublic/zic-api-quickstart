#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Get an OAuth bearer token from the ZIC appliance's Keycloak.
# Prints the access_token to stdout on success; non-zero exit on failure.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

# Auto-load ../../.env if it exists.
ENV_FILE="$(cd "$(dirname "$0")/../.." && pwd)/.env"
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    set -a; source "$ENV_FILE"; set +a
fi

: "${ZIC_HOST:?ZIC_HOST is required (set in .env or export it)}"
: "${ZIC_USERNAME:?ZIC_USERNAME is required}"
: "${ZIC_PASSWORD:?ZIC_PASSWORD is required}"

ZIC_TOKEN_URL="${ZIC_TOKEN_URL:-https://${ZIC_HOST}/auth/realms/zerto/protocol/openid-connect/token}"
ZIC_CLIENT_ID="${ZIC_CLIENT_ID:-zerto-client}"

# -k skips self-signed cert verification; remove in production.
RESPONSE=$(curl -sS -k -X POST "$ZIC_TOKEN_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "scope=openid" \
    --data-urlencode "client_id=${ZIC_CLIENT_ID}" \
    --data-urlencode "username=${ZIC_USERNAME}" \
    --data-urlencode "password=${ZIC_PASSWORD}")

if command -v jq >/dev/null 2>&1; then
    TOKEN=$(echo "$RESPONSE" | jq -r '.access_token // empty')
else
    TOKEN=$(echo "$RESPONSE" | grep -o '"access_token":"[^"]*"' | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
fi

if [[ -z "$TOKEN" ]]; then
    echo "ERROR: no access_token in response" >&2
    echo "Response was:" >&2
    echo "$RESPONSE" >&2
    exit 1
fi

echo "$TOKEN"
