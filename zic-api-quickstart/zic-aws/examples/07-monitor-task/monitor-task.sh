#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Poll a ZIC task until it reaches a terminal state.
# Usage:  ./monitor-task.sh '<task-id>'
#
# Exit codes:
#   0 — taskCompletionStatus == Success
#   1 — taskCompletionStatus in {Failed, Cancelled, PartialSuccess}
#   2 — bad usage
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
    echo "Usage: $0 '<task-id>'" >&2
    exit 2
fi

TASK_ID="$1"
INTERVAL="${POLL_INTERVAL:-5}"

ENV_FILE="$(cd "$(dirname "$0")/../.." && pwd)/.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

: "${ZIC_HOST:?ZIC_HOST is required}"
ZIC_API_BASE="${ZIC_API_BASE:-https://${ZIC_HOST}/zic/api/v1}"

# Re-auth each iteration — tokens are ~60s lived.
get_fresh_token() {
    "$(dirname "$0")/../01-get-token/get-token.sh"
}

while :; do
    TOKEN=$(get_fresh_token)
    RESPONSE=$(curl -sS -k -X GET "${ZIC_API_BASE}/tasks/${TASK_ID}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Accept: application/json")

    if command -v jq >/dev/null 2>&1; then
        STATUS=$(echo "$RESPONSE" | jq -r '.status // "?"')
        PROGRESS=$(echo "$RESPONSE" | jq -r '.progress // 0')
        OP=$(echo "$RESPONSE" | jq -r '.operationType // "?"')
        COMPLETION=$(echo "$RESPONSE" | jq -r '.taskResult.taskCompletionStatus // ""')
        REASON=$(echo "$RESPONSE" | jq -r '.taskResult.failureReason // ""')
    else
        STATUS=$(echo "$RESPONSE" | grep -oE '"status":"[^"]*"' | head -n1 | sed 's/.*:"\([^"]*\)"/\1/')
        PROGRESS=$(echo "$RESPONSE" | grep -oE '"progress":[0-9.]+' | head -n1 | sed 's/.*://')
        OP=""
        COMPLETION=""
        REASON=""
    fi

    TS=$(date +"%H:%M:%S")
    printf "[%s]  status=%-30s progress=%5s  operationType=%s\n" \
        "$TS" "$STATUS" "$PROGRESS" "$OP"

    if [[ "$STATUS" == "Completed" ]]; then
        if [[ "$COMPLETION" == "Success" ]]; then
            echo "✓ Task completed with status: Success"
            exit 0
        else
            echo "✗ Task completed with status: $COMPLETION" >&2
            if [[ -n "$REASON" ]]; then
                echo "  failureReason: $REASON" >&2
            fi
            exit 1
        fi
    fi

    sleep "$INTERVAL"
done
