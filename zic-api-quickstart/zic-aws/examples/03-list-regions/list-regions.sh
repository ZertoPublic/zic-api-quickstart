#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# List AWS regions the ZIC appliance is enabled for.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

ENV_FILE="$(cd "$(dirname "$0")/../.." && pwd)/.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

: "${ZIC_HOST:?ZIC_HOST is required}"
ZIC_API_BASE="${ZIC_API_BASE:-https://${ZIC_HOST}/zic/api/v1}"

TOKEN=$("$(dirname "$0")/../01-get-token/get-token.sh")

RESPONSE=$(curl -sS -k -X GET "${ZIC_API_BASE}/regions" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/json")

if ! command -v jq >/dev/null 2>&1; then
    echo "$RESPONSE"
    exit 0
fi

COUNT=$(echo "$RESPONSE" | jq '.regions | length')
if [[ "$COUNT" == "0" ]]; then
    echo "(no regions enabled on this appliance)"
    exit 0
fi

echo "$COUNT region(s) enabled:"
echo
printf "%-16s | %s\n" "id" "name"
printf "%-16s-+-%s\n" "----------------" "----------------------------------"
echo "$RESPONSE" | jq -r '.regions[] | "\(.id // "?")\t\(.name // "?")"' | \
    awk -F'\t' '{ printf "%-16s | %s\n", $1, $2 }'
