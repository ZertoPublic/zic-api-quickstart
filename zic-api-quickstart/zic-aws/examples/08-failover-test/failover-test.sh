#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Kick off a non-disruptive failover test on a VPG.
# Usage:  ./failover-test.sh '<vpgId>'
#
# Hardcoded to Zic-Action: failoverTest — non-disruptive.
# DO NOT change ZIC_ACTION to "failover" in this script unless you know
# exactly what that will do to your production workload.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
    echo "Usage: $0 '<vpgId>'" >&2
    exit 2
fi

VPG_ID="$1"
ZIC_ACTION="failoverTest"

ENV_FILE="$(cd "$(dirname "$0")/../.." && pwd)/.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

: "${ZIC_HOST:?ZIC_HOST is required}"
ZIC_API_BASE="${ZIC_API_BASE:-https://${ZIC_HOST}/zic/api/v1}"

TOKEN=$("$(dirname "$0")/../01-get-token/get-token.sh")
AUTH="Authorization: Bearer $TOKEN"

# Step 1: list checkpoints and pick the latest.
echo "→ GET    ${ZIC_API_BASE}/vpgs/${VPG_ID}/checkpoints"
CHECKPOINTS=$(curl -sS -k -X GET "${ZIC_API_BASE}/vpgs/${VPG_ID}/checkpoints" \
    -H "$AUTH" -H "Accept: application/json")

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required to pick a checkpoint." >&2
    exit 1
fi

# The checkpoints endpoint isn't exhaustively schema'd in the swagger;
# try a few common envelope shapes.
CP_ID=$(echo "$CHECKPOINTS" | jq -r '
    (.checkpoints // . // [])
    | (if type=="array" then . else .checkpoints // [] end)
    | sort_by(.timeStamp // .TimeStamp // 0)
    | last
    | (.checkpointId.id // .checkpointId // .CheckpointId // empty)
' 2>/dev/null || true)
CP_TS=$(echo "$CHECKPOINTS" | jq -r '
    (.checkpoints // . // [])
    | (if type=="array" then . else .checkpoints // [] end)
    | sort_by(.timeStamp // .TimeStamp // 0)
    | last
    | (.timeStamp // .TimeStamp // empty)
' 2>/dev/null || true)

if [[ -z "$CP_ID" || "$CP_ID" == "null" ]]; then
    echo "ERROR: couldn't pick a checkpoint. Raw response:" >&2
    echo "$CHECKPOINTS" | head -c 2000 >&2
    exit 1
fi
echo "  picked checkpoint $CP_ID  ($CP_TS)"
echo

# Step 2: PUT failover with Zic-Action header.
echo "→ PUT    ${ZIC_API_BASE}/vpgs/${VPG_ID}/failover  [Zic-Action: ${ZIC_ACTION}]"
BODY=$(printf '{"recoveryOperation":{"checkpointId":%s,"shutdownProtectedVmsOnCommit":false,"reverseProtectVpgOnCommit":false}}' "$CP_ID")
HTTP_CODE=$(curl -sS -k -o /tmp/zic-failover-resp.txt -w "%{http_code}" \
    -X PUT "${ZIC_API_BASE}/vpgs/${VPG_ID}/failover" \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -H "Zic-Action: ${ZIC_ACTION}" \
    -d "$BODY")

if [[ "$HTTP_CODE" != "202" ]]; then
    echo "ERROR: expected 202 Accepted, got $HTTP_CODE" >&2
    echo "Response:" >&2
    cat /tmp/zic-failover-resp.txt >&2
    rm -f /tmp/zic-failover-resp.txt
    exit 1
fi
echo "  202 Accepted — failover test queued"
echo

# Step 3: find the task and follow it.
echo "→ following task ..."
sleep 2
TASKS=$(curl -sS -k -X GET "${ZIC_API_BASE}/tasks?top=1" \
    -H "$AUTH" -H "Accept: application/json")
TASK_ID=$(echo "$TASKS" | jq -r '.tasks[0].taskId.id // empty')

if [[ -z "$TASK_ID" ]]; then
    echo "WARNING: couldn't auto-find the task. Check tasks list manually." >&2
    rm -f /tmp/zic-failover-resp.txt
    exit 0
fi

"$(dirname "$0")/../07-monitor-task/monitor-task.sh" "$TASK_ID" || {
    rm -f /tmp/zic-failover-resp.txt
    exit 1
}

echo
echo "✓ Failover test is now running."
echo
echo "When ready to tear down the test, run:"
echo
echo "  curl -k -X PUT \\"
echo "    -H \"Authorization: Bearer \$(./../01-get-token/get-token.sh)\" \\"
echo "    -H \"Content-Type: application/json\" \\"
echo "    -H \"Zic-Action: failoverTestStop\" \\"
echo "    -d '{\"recoveryOperation\":{\"checkpointId\":0,\"shutdownProtectedVmsOnCommit\":false,\"reverseProtectVpgOnCommit\":false}}' \\"
echo "    ${ZIC_API_BASE}/vpgs/${VPG_ID}/failover"

rm -f /tmp/zic-failover-resp.txt
