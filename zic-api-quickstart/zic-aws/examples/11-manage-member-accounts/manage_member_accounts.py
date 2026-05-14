#!/usr/bin/env python3
"""Manage member accounts on a ZIC v2 appliance.

Usage:
    python3 manage_member_accounts.py add  <accountId> <externalId> [description]
    python3 manage_member_accounts.py edit <accountId> <externalId> [description]
    python3 manage_member_accounts.py rm   <accountId>
"""
from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

import urllib3
import requests

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "01-get-token"))
from get_token import get_token  # type: ignore  # noqa: E402


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    action = sys.argv[1]

    host = os.environ["ZIC_HOST"]
    v2_base = f"https://{host}/zic/api/v2"
    verify_tls = os.environ.get("ZIC_VERIFY_TLS", "false").lower() in ("1", "true", "yes")

    if not verify_tls:
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    token = get_token()
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }

    if action == "add":
        if len(sys.argv) < 4:
            print("ERROR: 'add' needs <accountId> <externalId> [description]", file=sys.stderr)
            return 2
        account_id, external_id = sys.argv[2], sys.argv[3]
        desc = sys.argv[4] if len(sys.argv) > 4 else None
        body = {"accountId": {"id": account_id}, "externalId": external_id}
        if desc:
            body["description"] = desc
        print(f"→ POST   {v2_base}/zicconfiguration/memberaccounts")
        resp = requests.post(
            f"{v2_base}/zicconfiguration/memberaccounts",
            headers=headers, json=body, verify=verify_tls, timeout=60,
        )

    elif action == "edit":
        if len(sys.argv) < 4:
            print("ERROR: 'edit' needs <accountId> <externalId> [description]", file=sys.stderr)
            return 2
        account_id, external_id = sys.argv[2], sys.argv[3]
        desc = sys.argv[4] if len(sys.argv) > 4 else None
        body = {"externalId": external_id}
        if desc:
            body["description"] = desc
        print(f"→ PUT    {v2_base}/zicconfiguration/memberaccounts/{account_id}")
        resp = requests.put(
            f"{v2_base}/zicconfiguration/memberaccounts/{account_id}",
            headers=headers, json=body, verify=verify_tls, timeout=60,
        )

    elif action == "rm":
        if len(sys.argv) < 3:
            print("ERROR: 'rm' needs <accountId>", file=sys.stderr)
            return 2
        account_id = sys.argv[2]
        print(f"→ DELETE {v2_base}/zicconfiguration/memberaccounts/{account_id}")
        resp = requests.delete(
            f"{v2_base}/zicconfiguration/memberaccounts/{account_id}",
            headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
            verify=verify_tls, timeout=60,
        )

    else:
        print(__doc__)
        return 2

    if resp.status_code != 202:
        print(f"ERROR: expected 202, got {resp.status_code}", file=sys.stderr)
        print(f"Response: {resp.text}", file=sys.stderr)
        return 1
    print(f"  {resp.status_code} — queued\n")

    # Find the task and follow it via the monitor script.
    print("→ following task ...")
    time.sleep(2)
    tasks_resp = requests.get(
        f"{v2_base}/tasks", params={"top": 1},
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        verify=verify_tls, timeout=30,
    )
    tasks_resp.raise_for_status()
    tasks = (tasks_resp.json() or {}).get("tasks") or []
    if not tasks:
        print("WARNING: couldn't auto-find the task.", file=sys.stderr)
        return 0
    task_id = (tasks[0].get("taskId") or {}).get("id")

    # Force the monitor onto v2.
    env = os.environ.copy()
    env["ZIC_API_BASE"] = v2_base
    monitor = Path(__file__).resolve().parents[1] / "07-monitor-task" / "monitor_task.py"
    return subprocess.call([sys.executable, str(monitor), task_id], env=env)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except requests.HTTPError as exc:
        print(f"ERROR: HTTP {exc.response.status_code}: {exc.response.text}", file=sys.stderr)
        sys.exit(1)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
