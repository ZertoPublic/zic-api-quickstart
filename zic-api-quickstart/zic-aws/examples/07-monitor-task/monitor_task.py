#!/usr/bin/env python3
"""Poll a ZIC task until it reaches a terminal state.

Usage:  python3 monitor_task.py '<task-id>'

Exit codes:
  0 — taskCompletionStatus == Success
  1 — taskCompletionStatus in {Failed, Cancelled, PartialSuccess}
  2 — bad usage / unrecoverable error
"""
from __future__ import annotations

import os
import sys
import time
from datetime import datetime
from pathlib import Path

import urllib3
import requests

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "01-get-token"))
from get_token import get_token  # type: ignore  # noqa: E402


def main(task_id: str) -> int:
    host = os.environ["ZIC_HOST"]
    api_base = os.environ.get("ZIC_API_BASE", f"https://{host}/zic/api/v1")
    verify_tls = os.environ.get("ZIC_VERIFY_TLS", "false").lower() in ("1", "true", "yes")
    interval = int(os.environ.get("POLL_INTERVAL", "5"))

    if not verify_tls:
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    while True:
        token = get_token()
        resp = requests.get(
            f"{api_base}/tasks/{task_id}",
            headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
            verify=verify_tls,
            timeout=30,
        )
        resp.raise_for_status()
        task = resp.json() or {}

        status = task.get("status", "?")
        progress = task.get("progress", 0.0)
        op = task.get("operationType", "?")
        result = task.get("taskResult") or {}
        completion = result.get("taskCompletionStatus")
        reason = result.get("failureReason")

        ts = datetime.now().strftime("%H:%M:%S")
        print(f"[{ts}]  status={status:<30} progress={progress:>5.1f}  operationType={op}")

        if status == "Completed":
            if completion == "Success":
                print("✓ Task completed with status: Success")
                return 0
            print(f"✗ Task completed with status: {completion}", file=sys.stderr)
            if reason:
                print(f"  failureReason: {reason}", file=sys.stderr)
            return 1

        time.sleep(interval)


if __name__ == "__main__":
    if len(sys.argv) < 2 or not sys.argv[1]:
        print("Usage: monitor_task.py '<task-id>'", file=sys.stderr)
        sys.exit(2)
    try:
        sys.exit(main(sys.argv[1]))
    except requests.HTTPError as exc:
        print(f"ERROR: HTTP {exc.response.status_code}: {exc.response.text}", file=sys.stderr)
        sys.exit(2)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(2)
