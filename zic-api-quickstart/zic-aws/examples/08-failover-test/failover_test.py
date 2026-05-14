#!/usr/bin/env python3
"""Kick off a non-disruptive failover test on a VPG.

Usage:  python3 failover_test.py '<vpgId>'

Hardcoded to Zic-Action: failoverTest — non-disruptive.
DO NOT change ZIC_ACTION to "failover" in this script without
understanding what it will do to production.
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

ZIC_ACTION = "failoverTest"  # non-disruptive — see README


def pick_latest_checkpoint(payload) -> tuple[int | str | None, str | None]:
    """Try a few common envelope shapes to find the latest checkpoint."""
    if isinstance(payload, dict):
        candidates = payload.get("checkpoints") or payload.get("Checkpoints") or []
    elif isinstance(payload, list):
        candidates = payload
    else:
        candidates = []

    if not candidates:
        return None, None

    def ts(cp):
        return cp.get("timeStamp") or cp.get("TimeStamp") or ""

    latest = sorted(candidates, key=ts)[-1]
    cp_id_field = latest.get("checkpointId") or latest.get("CheckpointId")
    if isinstance(cp_id_field, dict):
        cp_id = cp_id_field.get("id") or cp_id_field.get("Id")
    else:
        cp_id = cp_id_field
    return cp_id, ts(latest)


def main(vpg_id: str) -> int:
    host = os.environ["ZIC_HOST"]
    api_base = os.environ.get("ZIC_API_BASE", f"https://{host}/zic/api/v1")
    verify_tls = os.environ.get("ZIC_VERIFY_TLS", "false").lower() in ("1", "true", "yes")

    if not verify_tls:
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    token = get_token()
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}

    # 1) List checkpoints.
    print(f"→ GET    {api_base}/vpgs/{vpg_id}/checkpoints")
    resp = requests.get(f"{api_base}/vpgs/{vpg_id}/checkpoints",
                        headers=headers, verify=verify_tls, timeout=30)
    resp.raise_for_status()
    cp_id, cp_ts = pick_latest_checkpoint(resp.json())
    if cp_id is None:
        print("ERROR: no checkpoints available on this VPG", file=sys.stderr)
        return 1
    print(f"  picked checkpoint {cp_id}  ({cp_ts})\n")

    # 2) PUT failover.
    body = {
        "recoveryOperation": {
            "checkpointId":                cp_id,
            "shutdownProtectedVmsOnCommit": False,
            "reverseProtectVpgOnCommit":    False,
        }
    }
    print(f"→ PUT    {api_base}/vpgs/{vpg_id}/failover  [Zic-Action: {ZIC_ACTION}]")
    resp = requests.put(
        f"{api_base}/vpgs/{vpg_id}/failover",
        headers={**headers, "Content-Type": "application/json", "Zic-Action": ZIC_ACTION},
        json=body,
        verify=verify_tls,
        timeout=60,
    )
    if resp.status_code != 202:
        print(f"ERROR: expected 202 Accepted, got {resp.status_code}", file=sys.stderr)
        print(f"Response body: {resp.text}", file=sys.stderr)
        return 1
    print("  202 Accepted — failover test queued\n")

    # 3) Find the task and follow it.
    print("→ following task ...")
    time.sleep(2)
    resp = requests.get(f"{api_base}/tasks", params={"top": 1},
                        headers=headers, verify=verify_tls, timeout=30)
    resp.raise_for_status()
    tasks = (resp.json() or {}).get("tasks") or []
    if not tasks:
        print("WARNING: couldn't auto-find the task.", file=sys.stderr)
        return 0
    task_id = (tasks[0].get("taskId") or {}).get("id")

    monitor = Path(__file__).resolve().parents[1] / "07-monitor-task" / "monitor_task.py"
    rc = subprocess.call([sys.executable, str(monitor), task_id])
    if rc != 0:
        return rc

    print()
    print("✓ Failover test is now running.")
    print()
    print("When ready to tear down the test, run:")
    print(f"  curl -k -X PUT \\")
    print(f"    -H \"Authorization: Bearer $(./../01-get-token/get-token.sh)\" \\")
    print(f"    -H \"Content-Type: application/json\" \\")
    print(f"    -H \"Zic-Action: failoverTestStop\" \\")
    print(f"    -d '{{\"recoveryOperation\":{{\"checkpointId\":0,\"shutdownProtectedVmsOnCommit\":false,\"reverseProtectVpgOnCommit\":false}}}}' \\")
    print(f"    {api_base}/vpgs/{vpg_id}/failover")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2 or not sys.argv[1]:
        print("Usage: failover_test.py '<vpgId>'", file=sys.stderr)
        sys.exit(2)
    try:
        sys.exit(main(sys.argv[1]))
    except requests.HTTPError as exc:
        print(f"ERROR: HTTP {exc.response.status_code}: {exc.response.text}", file=sys.stderr)
        sys.exit(1)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
