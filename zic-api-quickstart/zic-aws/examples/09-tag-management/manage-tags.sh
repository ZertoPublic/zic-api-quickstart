#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Manage recovery.default.tags on an existing VPG.
# Read-modify-write: GET full config → mutate tags → PUT it back → poll task.
#
# Usage:
#   ./manage-tags.sh <vpg-name>                       # show current tags
#   ./manage-tags.sh <vpg-name> add  <key> <value>    # add or update one tag (upsert by key)
#   ./manage-tags.sh <vpg-name> rm   <key>            # remove one tag by key
#   ./manage-tags.sh <vpg-name> set  '<tags-json>'    # replace all tags
#   ./manage-tags.sh <vpg-name> clear                 # remove all tags
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

usage() {
    sed -n '4,12p' "$0"
    exit "${1:-2}"
}

if [[ $# -lt 1 ]]; then usage; fi
if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required for this script (tag-array surgery)." >&2
    exit 1
fi

VPG_NAME="$1"
ACTION="${2:-show}"

ENV_FILE="$(cd "$(dirname "$0")/../.." && pwd)/.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

: "${ZIC_HOST:?ZIC_HOST is required}"
ZIC_API_BASE="${ZIC_API_BASE:-https://${ZIC_HOST}/zic/api/v1}"

TOKEN=$("$(dirname "$0")/../01-get-token/get-token.sh")
AUTH="Authorization: Bearer $TOKEN"

# 1) GET all VPGs, pick the one whose general.name matches.
echo "→ GET    ${ZIC_API_BASE}/vpgs"
VPGS=$(curl -sS -k -X GET "${ZIC_API_BASE}/vpgs" \
    -H "$AUTH" -H "Accept: application/json")

VPG=$(echo "$VPGS" | jq --arg n "$VPG_NAME" \
    '.vpgs[] | select(.vpgInfo.general.name == $n)')

if [[ -z "$VPG" || "$VPG" == "null" ]]; then
    echo "ERROR: no VPG found with name '$VPG_NAME'." >&2
    echo "Available VPGs:" >&2
    echo "$VPGS" | jq -r '.vpgs[].vpgInfo.general.name' >&2
    exit 1
fi

VPG_ID=$(echo "$VPG" | jq -r '.vpgId')
echo "  resolved vpgId: $VPG_ID"

CURRENT_TAGS=$(echo "$VPG" | jq '.vpgInfo.recovery.default.tags // []')

# Always print current tags first.
echo
echo "Current tags:"
if [[ "$(echo "$CURRENT_TAGS" | jq 'length')" == "0" ]]; then
    echo "  (none)"
else
    echo "$CURRENT_TAGS" | jq -r '.[] | "  \(.tagKey) = \(.tagValue)"'
fi

if [[ "$ACTION" == "show" ]]; then
    exit 0
fi

# 2) Compute the new tag set in memory.
case "$ACTION" in
    add)
        if [[ $# -lt 4 ]]; then
            echo "ERROR: 'add' needs <key> and <value>" >&2
            exit 2
        fi
        KEY="$3"; VAL="$4"
        if [[ -z "$KEY" ]]; then
            echo "ERROR: tag key must be non-empty (swagger requires minLength: 1)." >&2
            exit 2
        fi
        # Upsert: drop any existing entry with that key, then append.
        NEW_TAGS=$(echo "$CURRENT_TAGS" | jq --arg k "$KEY" --arg v "$VAL" \
            'map(select(.tagKey != $k)) + [{"tagKey": $k, "tagValue": $v}]')
        ;;
    rm)
        if [[ $# -lt 3 ]]; then
            echo "ERROR: 'rm' needs <key>" >&2
            exit 2
        fi
        KEY="$3"
        NEW_TAGS=$(echo "$CURRENT_TAGS" | jq --arg k "$KEY" \
            'map(select(.tagKey != $k))')
        ;;
    set)
        if [[ $# -lt 3 ]]; then
            echo "ERROR: 'set' needs the new tags array as a JSON string" >&2
            exit 2
        fi
        # Validate it's a JSON array of {tagKey, tagValue} entries.
        NEW_TAGS=$(echo "$3" | jq '.' 2>/dev/null) || {
            echo "ERROR: 'set' argument is not valid JSON." >&2
            exit 2
        }
        if [[ "$(echo "$NEW_TAGS" | jq 'type')" != '"array"' ]]; then
            echo "ERROR: 'set' argument must be a JSON array." >&2
            exit 2
        fi
        ;;
    clear)
        NEW_TAGS='[]'
        ;;
    *)
        echo "ERROR: unknown action '$ACTION'" >&2
        usage 2
        ;;
esac

echo
echo "New tags (about to be applied):"
if [[ "$(echo "$NEW_TAGS" | jq 'length')" == "0" ]]; then
    echo "  (none)"
else
    echo "$NEW_TAGS" | jq -r '.[] | "  \(.tagKey) = \(.tagValue)"'
fi

# 3) Build the EditVpgRequest body: copy protected/replication/recovery verbatim,
#    strip the immutable fields from general.
BODY=$(echo "$VPG" | jq --argjson newTags "$NEW_TAGS" '
    {
        vpg: {
            general: {
                name:        .vpgInfo.general.name,
                description: .vpgInfo.general.description
            },
            protectedResources: .vpgInfo.protectedResources,
            replication:        .vpgInfo.replication,
            recovery: (
                .vpgInfo.recovery
                | .default.tags = $newTags
            )
        }
    }
')

# 4) PUT the modified body back.
echo
echo "→ PUT    ${ZIC_API_BASE}/vpgs/${VPG_ID}"
HTTP_CODE=$(curl -sS -k -o /tmp/zic-edit-resp.txt -w "%{http_code}" \
    -X PUT "${ZIC_API_BASE}/vpgs/${VPG_ID}" \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$BODY")

if [[ "$HTTP_CODE" != "202" ]]; then
    echo "ERROR: expected 202 Accepted, got $HTTP_CODE" >&2
    echo "Response:" >&2
    cat /tmp/zic-edit-resp.txt >&2
    rm -f /tmp/zic-edit-resp.txt
    exit 1
fi
echo "  202 Accepted — update queued"

# 5) Find the resulting task and poll it.
echo
echo "→ following task ..."
sleep 2
TASKS=$(curl -sS -k -X GET "${ZIC_API_BASE}/tasks?top=1" \
    -H "$AUTH" -H "Accept: application/json")
TASK_ID=$(echo "$TASKS" | jq -r '.tasks[0].taskId.id // empty')

if [[ -z "$TASK_ID" ]]; then
    echo "WARNING: couldn't auto-find the task. Check tasks list manually." >&2
    rm -f /tmp/zic-edit-resp.txt
    exit 0
fi

"$(dirname "$0")/../07-monitor-task/monitor-task.sh" "$TASK_ID" || {
    rm -f /tmp/zic-edit-resp.txt
    exit 1
}

rm -f /tmp/zic-edit-resp.txt
