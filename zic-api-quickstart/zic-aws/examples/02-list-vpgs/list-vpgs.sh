#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# List every VPG on the appliance.
# Prints: name | vpgState | protectionStatus | actualRpo | vmCount
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

ENV_FILE="$(cd "$(dirname "$0")/../.." && pwd)/.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

: "${ZIC_HOST:?ZIC_HOST is required}"
ZIC_API_BASE="${ZIC_API_BASE:-https://${ZIC_HOST}/zic/api/v1}"

TOKEN=$("$(dirname "$0")/../01-get-token/get-token.sh")

RESPONSE=$(curl -sS -k -X GET "${ZIC_API_BASE}/vpgs" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/json")

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required for formatted output. Raw response:" >&2
    echo "$RESPONSE"
    exit 0
fi

COUNT=$(echo "$RESPONSE" | jq '.vpgs | length')
DEGRADED=$(echo "$RESPONSE" | jq '.vpgsWithoutData | length')

if [[ "$COUNT" == "0" && "$DEGRADED" == "0" ]]; then
    echo "(no VPGs on this appliance)"
    exit 0
fi

printf "%-26s | %-22s | %-22s | %-12s | %-3s\n" \
    "Name" "vpgState" "protectionStatus" "actualRpo" "VMs"
printf "%-26s-+-%-22s-+-%-22s-+-%-12s-+-%-3s\n" \
    "--------------------------" "----------------------" \
    "----------------------" "------------" "---"

echo "$RESPONSE" | jq -c '.vpgs[]' | while read -r vpg; do
    name=$(echo "$vpg" | jq -r '.vpgInfo.general.name // "?"')
    state=$(echo "$vpg" | jq -r '.vpgState // "?"')
    pstatus=$(echo "$vpg" | jq -r '.replicationInfo.replicationStatistics.protectionStatus // "?"')
    rpo=$(echo "$vpg" | jq -r '.replicationInfo.replicationStatistics.actualRpo // "?"')
    vms=$(echo "$vpg" | jq -r '.vpgInfo.protectedResources.vms | length')
    printf "%-26s | %-22s | %-22s | %-12s | %-3s\n" \
        "$name" "$state" "$pstatus" "$rpo" "$vms"
done

if [[ "$DEGRADED" != "0" ]]; then
    echo
    echo "⚠ $DEGRADED VPG(s) returned without full data (vpgsWithoutData)."
fi
