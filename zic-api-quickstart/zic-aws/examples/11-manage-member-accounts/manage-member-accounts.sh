#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Manage member accounts on a ZIC v2 appliance.
# v2-only: hits /api/v2/zicconfiguration/memberaccounts directly.
#
# Usage:
#   ./manage-member-accounts.sh add  <accountId> <externalId> [description]
#   ./manage-member-accounts.sh edit <accountId> <externalId> [description]
#   ./manage-member-accounts.sh rm   <accountId>
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

usage() {
    sed -n '6,10p' "$0"
    exit "${1:-2}"
}

if [[ $# -lt 1 ]]; then usage; fi

ACTION="$1"; shift

ENV_FILE="$(cd "$(dirname "$0")/../.." && pwd)/.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

: "${ZIC_HOST:?ZIC_HOST is required}"
V2_BASE="https://${ZIC_HOST}/zic/api/v2"

TOKEN=$("$(dirname "$0")/../01-get-token/get-token.sh")
AUTH="Authorization: Bearer $TOKEN"

case "$ACTION" in
    add)
        if [[ $# -lt 2 ]]; then
            echo "ERROR: 'add' needs <accountId> <externalId> [description]" >&2
            exit 2
        fi
        ACCOUNT_ID="$1"; EXTERNAL_ID="$2"; DESC="${3:-}"
        BODY=$(python3 -c "
import json,sys
b = {'accountId': {'id': sys.argv[1]}, 'externalId': sys.argv[2]}
if sys.argv[3]: b['description'] = sys.argv[3]
print(json.dumps(b))
" "$ACCOUNT_ID" "$EXTERNAL_ID" "$DESC")
        echo "→ POST   ${V2_BASE}/zicconfiguration/memberaccounts"
        HTTP=$(curl -sS -k -o /tmp/zic-ma-resp.txt -w "%{http_code}" \
            -X POST "${V2_BASE}/zicconfiguration/memberaccounts" \
            -H "$AUTH" -H "Content-Type: application/json" -d "$BODY")
        EXPECTED=202
        ;;
    edit)
        if [[ $# -lt 2 ]]; then
            echo "ERROR: 'edit' needs <accountId> <externalId> [description]" >&2
            exit 2
        fi
        ACCOUNT_ID="$1"; EXTERNAL_ID="$2"; DESC="${3:-}"
        BODY=$(python3 -c "
import json,sys
b = {'externalId': sys.argv[1]}
if sys.argv[2]: b['description'] = sys.argv[2]
print(json.dumps(b))
" "$EXTERNAL_ID" "$DESC")
        echo "→ PUT    ${V2_BASE}/zicconfiguration/memberaccounts/${ACCOUNT_ID}"
        HTTP=$(curl -sS -k -o /tmp/zic-ma-resp.txt -w "%{http_code}" \
            -X PUT "${V2_BASE}/zicconfiguration/memberaccounts/${ACCOUNT_ID}" \
            -H "$AUTH" -H "Content-Type: application/json" -d "$BODY")
        EXPECTED=202
        ;;
    rm)
        if [[ $# -lt 1 ]]; then
            echo "ERROR: 'rm' needs <accountId>" >&2
            exit 2
        fi
        ACCOUNT_ID="$1"
        echo "→ DELETE ${V2_BASE}/zicconfiguration/memberaccounts/${ACCOUNT_ID}"
        HTTP=$(curl -sS -k -o /tmp/zic-ma-resp.txt -w "%{http_code}" \
            -X DELETE "${V2_BASE}/zicconfiguration/memberaccounts/${ACCOUNT_ID}" \
            -H "$AUTH")
        EXPECTED=202
        ;;
    *)
        usage 2
        ;;
esac

if [[ "$HTTP" != "$EXPECTED" ]]; then
    echo "ERROR: expected $EXPECTED, got $HTTP" >&2
    echo "Response:" >&2
    cat /tmp/zic-ma-resp.txt >&2
    rm -f /tmp/zic-ma-resp.txt
    exit 1
fi
echo "  ${HTTP} — queued"
echo

# Find the resulting task and poll.
echo "→ following task ..."
sleep 2
TASKS=$(curl -sS -k -X GET "${V2_BASE}/tasks?top=1" \
    -H "$AUTH" -H "Accept: application/json")
TASK_ID=$(echo "$TASKS" | python3 -c \
    "import json,sys; t=json.load(sys.stdin).get('tasks',[]); print(t[0]['taskId']['id'] if t else '')")

if [[ -z "$TASK_ID" ]]; then
    echo "WARNING: couldn't auto-find the task. Check tasks list manually." >&2
    rm -f /tmp/zic-ma-resp.txt
    exit 0
fi

# Hand off to the monitor — but force it onto v2 since the env may say v1
ZIC_API_BASE="${V2_BASE}" "$(dirname "$0")/../07-monitor-task/monitor-task.sh" "$TASK_ID" || {
    rm -f /tmp/zic-ma-resp.txt
    exit 1
}

rm -f /tmp/zic-ma-resp.txt
