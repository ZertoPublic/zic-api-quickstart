#!/usr/bin/env python3
"""Create a VPG via the ZIC API (single POST + task lookup)."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import urllib3
import requests

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "01-get-token"))
from get_token import get_token  # type: ignore  # noqa: E402

HERE = Path(__file__).resolve().parent
DEFAULT_BODY = HERE / "default-vpg-body.json"


def main(body_path: Path) -> int:
    if not body_path.exists():
        print(f"ERROR: body file not found: {body_path}", file=sys.stderr)
        return 1

    raw = body_path.read_text()
    if "REPLACE_ME" in raw:
        print(f"ERROR: {body_path} still contains REPLACE_ME placeholders.", file=sys.stderr)
        print("Run examples 03 and 04 to discover the right values for your environment.",
              file=sys.stderr)
        return 1

    body = json.loads(raw)

    host = os.environ["ZIC_HOST"]
    api_base = os.environ.get("ZIC_API_BASE", f"https://{host}/zic/api/v1")
    verify_tls = os.environ.get("ZIC_VERIFY_TLS", "false").lower() in ("1", "true", "yes")

    if not verify_tls:
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    token = get_token()
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }

    # POST — should return 202 with no body.
    print(f"→ POST {api_base}/vpgs")
    resp = requests.post(f"{api_base}/vpgs", headers=headers, json=body,
                         verify=verify_tls, timeout=60)
    if resp.status_code != 202:
        print(f"ERROR: expected 202 Accepted, got {resp.status_code}", file=sys.stderr)
        print(f"Response body: {resp.text}", file=sys.stderr)
        return 1
    print("  202 Accepted — VPG creation queued\n")

    # Look up the most recent task to follow.
    print(f"→ GET {api_base}/tasks?top=1")
    resp = requests.get(f"{api_base}/tasks", params={"top": 1},
                        headers={"Authorization": f"Bearer {token}",
                                 "Accept": "application/json"},
                        verify=verify_tls, timeout=30)
    resp.raise_for_status()
    tasks = (resp.json() or {}).get("tasks") or []
    if not tasks:
        print("WARNING: no recent task found. The VPG may still be processing.",
              file=sys.stderr)
        return 0

    task = tasks[0]
    task_id = (task.get("taskId") or {}).get("id")
    op = task.get("operationType")
    print(f"  most recent task: {task_id}  (operationType={op})\n")
    print("Hand this task ID to example 07 to watch it complete:")
    print(f"  cd ../07-monitor-task && python3 monitor_task.py '{task_id}'")
    return 0


if __name__ == "__main__":
    body_arg = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_BODY
    try:
        sys.exit(main(body_arg))
    except requests.HTTPError as exc:
        print(f"ERROR: HTTP {exc.response.status_code}: {exc.response.text}", file=sys.stderr)
        sys.exit(1)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
