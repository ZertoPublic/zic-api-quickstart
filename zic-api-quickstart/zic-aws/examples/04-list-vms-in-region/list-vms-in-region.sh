#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# List EC2 VMs in a ZIC-enabled region, with protection state.
# Usage:  ./list-vms-in-region.sh <regionId>
#         ./list-vms-in-region.sh us-east-1 Env prod   # with tag filter
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <regionId> [tagName tagValue]" >&2
    exit 2
fi

REGION="$1"
TAG_NAME="${2:-}"
TAG_VALUE="${3:-}"

ENV_FILE="$(cd "$(dirname "$0")/../.." && pwd)/.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

: "${ZIC_HOST:?ZIC_HOST is required}"
ZIC_API_BASE="${ZIC_API_BASE:-https://${ZIC_HOST}/zic/api/v1}"

TOKEN=$("$(dirname "$0")/../01-get-token/get-token.sh")

URL="${ZIC_API_BASE}/regions/${REGION}/resources/vms"
if [[ -n "$TAG_NAME" && -n "$TAG_VALUE" ]]; then
    URL="${URL}?tagName=${TAG_NAME}&tagValue=${TAG_VALUE}"
fi

RESPONSE=$(curl -sS -k -X GET "$URL" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/json")

if ! command -v jq >/dev/null 2>&1; then
    echo "$RESPONSE"
    exit 0
fi

COUNT=$(echo "$RESPONSE" | jq '.vms | length')
if [[ "$COUNT" == "0" ]]; then
    echo "(no VMs in region $REGION)"
    exit 0
fi

echo "Region: $REGION  ($COUNT VMs)"
echo
printf "%-22s | %-25s | %-9s | %s\n" "vmId" "name" "protected" "protectedInVpgs"
printf "%-22s-+-%-25s-+-%-9s-+-%s\n" \
    "----------------------" "-------------------------" \
    "---------" "----------------------"

echo "$RESPONSE" | jq -c '.vms[]' | while read -r vm; do
    vmid=$(echo "$vm" | jq -r '.vmPropertiesModel.id // .vmPropertiesModel.vmId // "?"')
    name=$(echo "$vm" | jq -r '.vmPropertiesModel.name // .vmPropertiesModel.vmName // "?"')
    prot=$(echo "$vm" | jq -r '.additionalPropertiesModel.isProtected // false')
    vpgs=$(echo "$vm" | jq -r '[.additionalPropertiesModel.protectedInVpgs[]?.id] | join(",") | if . == "" then "-" else . end')
    printf "%-22s | %-25s | %-9s | %s\n" "$vmid" "$name" "$prot" "$vpgs"
done
