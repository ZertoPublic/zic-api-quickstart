#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Multiplexing CLI for v2's account-scoped resource discovery endpoints.
#
# Usage:
#   ./list-account-resources.sh <accountId> regions
#   ./list-account-resources.sh <accountId> vms          <regionId> [tagName tagValue]
#   ./list-account-resources.sh <accountId> vnets        <regionId>
#   ./list-account-resources.sh <accountId> subnets      <regionId> <vnetId>
#   ./list-account-resources.sh <accountId> sgroups      <regionId> <vnetId>
#   ./list-account-resources.sh <accountId> keypairs     <regionId>
#   ./list-account-resources.sh <accountId> cmks         <regionId>
#   ./list-account-resources.sh <accountId> launchtemplates <regionId>
#   ./list-account-resources.sh <accountId> roles
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

if [[ $# -lt 2 ]]; then
    sed -n '5,16p' "$0"
    exit 2
fi

ACCOUNT_ID="$1"
RESOURCE="$2"
shift 2

ENV_FILE="$(cd "$(dirname "$0")/../.." && pwd)/.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

: "${ZIC_HOST:?ZIC_HOST is required}"
V2_BASE="https://${ZIC_HOST}/zic/api/v2"

TOKEN=$("$(dirname "$0")/../01-get-token/get-token.sh")
AUTH="Authorization: Bearer $TOKEN"

# Build the URL based on the resource type
case "$RESOURCE" in
    regions)
        URL="${V2_BASE}/accounts/${ACCOUNT_ID}/regions"
        JQ_PATH='.regions[]? | "  \(.id // "?")\t\(.name // "?")"'
        ;;
    vms)
        [[ $# -lt 1 ]] && { echo "ERROR: vms requires <regionId>" >&2; exit 2; }
        URL="${V2_BASE}/accounts/${ACCOUNT_ID}/regions/$1/resources/vms"
        if [[ $# -ge 3 ]]; then
            URL="${URL}?tagName=$2&tagValue=$3"
        fi
        JQ_PATH='.vms[]? | "  \(.vmPropertiesModel.id // "?")\t\(.vmPropertiesModel.name // "-")\tprotected=\(.additionalPropertiesModel.isProtected // false)"'
        ;;
    vnets)
        [[ $# -lt 1 ]] && { echo "ERROR: vnets requires <regionId>" >&2; exit 2; }
        URL="${V2_BASE}/accounts/${ACCOUNT_ID}/regions/$1/resources/vnets"
        JQ_PATH='.vnets[]? | "  \(.id // .vnetId // "?")\t\(.name // "-")"'
        ;;
    subnets)
        [[ $# -lt 2 ]] && { echo "ERROR: subnets requires <regionId> <vnetId>" >&2; exit 2; }
        URL="${V2_BASE}/accounts/${ACCOUNT_ID}/regions/$1/resources/vnets/$2/subnets"
        JQ_PATH='.subnets[]? | "  \(.id // .subnetId // "?")\t\(.name // "-")\t\(.availabilityZone // "-")"'
        ;;
    sgroups)
        [[ $# -lt 2 ]] && { echo "ERROR: sgroups requires <regionId> <vnetId>" >&2; exit 2; }
        URL="${V2_BASE}/accounts/${ACCOUNT_ID}/regions/$1/resources/vnets/$2/sgroups"
        JQ_PATH='.sgroups[]? | "  \(.id // "?")\t\(.name // "-")"'
        ;;
    keypairs)
        [[ $# -lt 1 ]] && { echo "ERROR: keypairs requires <regionId>" >&2; exit 2; }
        URL="${V2_BASE}/accounts/${ACCOUNT_ID}/regions/$1/resources/keypairs"
        JQ_PATH='.keypairs[]? | "  \(.name // "?")"'
        ;;
    cmks)
        [[ $# -lt 1 ]] && { echo "ERROR: cmks requires <regionId>" >&2; exit 2; }
        URL="${V2_BASE}/accounts/${ACCOUNT_ID}/regions/$1/resources/cmks"
        JQ_PATH='.cmks[]? | "  \(.id // .cmkId // .arn // "?")\t\(.alias // .name // "-")"'
        ;;
    launchtemplates)
        [[ $# -lt 1 ]] && { echo "ERROR: launchtemplates requires <regionId>" >&2; exit 2; }
        URL="${V2_BASE}/accounts/${ACCOUNT_ID}/regions/$1/resources/launchtemplates"
        JQ_PATH='.launchTemplates[]? | "  \(.id // "?")\t\(.name // "-")"'
        ;;
    roles)
        URL="${V2_BASE}/accounts/${ACCOUNT_ID}/resources/roles"
        JQ_PATH='.roles[]? | "  \(.name // "?")"'
        ;;
    *)
        echo "ERROR: unknown resource '$RESOURCE'" >&2
        exit 2
        ;;
esac

echo "→ GET    $URL"
RESPONSE=$(curl -sS -k -X GET "$URL" \
    -H "$AUTH" -H "Accept: application/json")

if ! command -v jq >/dev/null 2>&1; then
    echo "$RESPONSE"
    exit 0
fi

# Try to print human-readable lines; if jq path doesn't match, fall back to raw.
OUT=$(echo "$RESPONSE" | jq -r "$JQ_PATH" 2>/dev/null || true)
if [[ -z "$OUT" ]]; then
    echo "(empty or unexpected schema; raw response below)"
    echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
else
    echo "$OUT"
fi
