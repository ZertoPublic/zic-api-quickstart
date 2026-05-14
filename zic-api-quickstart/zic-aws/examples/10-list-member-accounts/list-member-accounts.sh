#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# List member accounts on a ZIC v2 appliance.
# Optionally also fetches usage statistics.
#
# Usage:
#   ./list-member-accounts.sh          # accounts only
#   ./list-member-accounts.sh --stats  # also pull /statistics
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

WITH_STATS=false
[[ "${1:-}" == "--stats" ]] && WITH_STATS=true

ENV_FILE="$(cd "$(dirname "$0")/../.." && pwd)/.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

: "${ZIC_HOST:?ZIC_HOST is required}"

# This example is v2-only. Build a v2 base URL regardless of what's
# in ZIC_API_BASE (which the user might still have on v1).
V2_BASE="https://${ZIC_HOST}/zic/api/v2"

TOKEN=$("$(dirname "$0")/../01-get-token/get-token.sh")
AUTH="Authorization: Bearer $TOKEN"

echo "→ GET    ${V2_BASE}/zicconfiguration/memberaccounts"
RESPONSE=$(curl -sS -k -X GET "${V2_BASE}/zicconfiguration/memberaccounts" \
    -H "$AUTH" -H "Accept: application/json")

if ! command -v jq >/dev/null 2>&1; then
    echo "$RESPONSE"
    exit 0
fi

COUNT=$(echo "$RESPONSE" | jq '.accounts | length')
if [[ "$COUNT" == "0" ]]; then
    echo "(no member accounts configured)"
    exit 0
fi

echo "  $COUNT member account(s):"
echo

# Pretty-print core info
echo "$RESPONSE" | jq -r '.accounts[] |
    "  accountId: \(.accountId.id // "?")
    description:    \(.description // "-")
    status:         \(.status // "?")\(if .statusDescription then "  — " + .statusDescription else "" end)
    externalId:     \(.externalId // "-")
    cmksPerRegion:  \(.cmksPerRegion // [] | length) configured
"'

if [[ "$WITH_STATS" == "true" ]]; then
    echo
    echo "→ GET    ${V2_BASE}/zicconfiguration/memberaccounts/statistics"
    STATS=$(curl -sS -k -X GET "${V2_BASE}/zicconfiguration/memberaccounts/statistics" \
        -H "$AUTH" -H "Accept: application/json")
    echo
    printf "  %-15s | %-13s | %-9s\n" "accountId" "protectedVms" "totalVpgs"
    printf "  %-15s-+-%-13s-+-%-9s\n" "---------------" "-------------" "---------"
    echo "$STATS" | jq -r '.accounts[] |
        "  \(.accountId.id // "?")\t\(.protectedVms // 0)\t\(.totalVpgs // 0)"' | \
        awk -F'\t' '{ printf "  %-15s | %-13s | %-9s\n", $1, $2, $3 }'
fi
