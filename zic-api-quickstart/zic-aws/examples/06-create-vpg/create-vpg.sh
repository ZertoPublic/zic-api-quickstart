#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Create a VPG via the ZIC API.
# Single POST. The 202 has no body, so we look up the resulting task
# via GET /tasks?topPerProperty=VpgId&top=1 immediately after.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$(cd "$SCRIPT_DIR/../.." && pwd)/.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

: "${ZIC_HOST:?ZIC_HOST is required}"
ZIC_API_BASE="${ZIC_API_BASE:-https://${ZIC_HOST}/zic/api/v1}"
BODY_FILE="${1:-${SCRIPT_DIR}/default-vpg-body.json}"

if [[ ! -f "$BODY_FILE" ]]; then
    echo "ERROR: body file not found: $BODY_FILE" >&2
    exit 1
fi

if grep -q "REPLACE_ME" "$BODY_FILE"; then
    echo "ERROR: $BODY_FILE still contains REPLACE_ME placeholders." >&2
    echo "Edit it first with real region IDs, AWS instance IDs, subnet, security group, etc." >&2
    echo "Run examples 03 and 04 to discover the right values for your environment." >&2
    exit 1
fi

TOKEN=$("$SCRIPT_DIR/../01-get-token/get-token.sh")
AUTH="Authorization: Bearer $TOKEN"

echo "→ POST $ZIC_API_BASE/vpgs"
HTTP_CODE=$(curl -sS -k -o /tmp/zic-create-resp.txt -w "%{http_code}" \
    -X POST "${ZIC_API_BASE}/vpgs" \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    --data-binary "@${BODY_FILE}")

if [[ "$HTTP_CODE" != "202" ]]; then
    echo "ERROR: expected 202 Accepted, got $HTTP_CODE" >&2
    echo "Response body:" >&2
    cat /tmp/zic-create-resp.txt >&2
    rm -f /tmp/zic-create-resp.txt
    exit 1
fi

echo "  202 Accepted — VPG creation queued"
echo

# Look up the most recent CreateVpg task to follow.
echo "→ GET $ZIC_API_BASE/tasks?top=1"
TASKS=$(curl -sS -k -X GET "${ZIC_API_BASE}/tasks?top=1" \
    -H "$AUTH" \
    -H "Accept: application/json")

if command -v jq >/dev/null 2>&1; then
    TASK_ID=$(echo "$TASKS" | jq -r '.tasks[0].taskId.id // empty')
    OP=$(echo "$TASKS" | jq -r '.tasks[0].operationType // empty')
else
    TASK_ID=$(echo "$TASKS" | grep -oE '"id":"[^"]*"' | head -n1 | sed 's/.*:"\([^"]*\)"/\1/')
    OP=""
fi

if [[ -z "$TASK_ID" ]]; then
    echo "WARNING: no recent task found. The VPG may still be processing — check the UI or run:" >&2
    echo "  curl -k -H \"Authorization: Bearer \$TOKEN\" ${ZIC_API_BASE}/tasks?top=5" >&2
    exit 0
fi

echo "  most recent task: $TASK_ID  (operationType=$OP)"
echo
echo "Hand this task ID to example 07 to watch it complete:"
echo "  cd ../07-monitor-task && ./monitor-task.sh '$TASK_ID'"

rm -f /tmp/zic-create-resp.txt
