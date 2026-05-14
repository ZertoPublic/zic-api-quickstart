#!/usr/bin/env python3
"""Manage recovery.default.tags on an existing VPG.

Read-modify-write: GET full config → mutate tags → PUT it back → poll task.

Usage:
    python3 manage_tags.py <vpg-name>                        # show current tags
    python3 manage_tags.py <vpg-name> add  <key> <value>     # add or update (upsert)
    python3 manage_tags.py <vpg-name> rm   <key>             # remove by key
    python3 manage_tags.py <vpg-name> set  '<tags-json>'     # replace all tags
    python3 manage_tags.py <vpg-name> clear                  # remove all tags
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import urllib3
import requests

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "01-get-token"))
from get_token import get_token  # type: ignore  # noqa: E402


def find_vpg_by_name(api_base: str, token: str, verify_tls: bool, name: str) -> dict:
    resp = requests.get(
        f"{api_base}/vpgs",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        verify=verify_tls,
        timeout=30,
    )
    resp.raise_for_status()
    vpgs = (resp.json() or {}).get("vpgs") or []
    for v in vpgs:
        if ((v.get("vpgInfo") or {}).get("general") or {}).get("name") == name:
            return v
    available = [(v.get("vpgInfo") or {}).get("general", {}).get("name", "?") for v in vpgs]
    raise SystemExit(
        f"ERROR: no VPG found with name '{name}'. Available: {available}"
    )


def print_tags(label: str, tags: list[dict]) -> None:
    print(f"{label}:")
    if not tags:
        print("  (none)")
        return
    for t in tags:
        print(f"  {t.get('tagKey', '?')} = {t.get('tagValue', '?')}")


def compute_new_tags(action: str, current: list[dict], args: list[str]) -> list[dict]:
    if action == "add":
        if len(args) < 2:
            raise SystemExit("ERROR: 'add' needs <key> <value>")
        key, value = args[0], args[1]
        if not key:
            raise SystemExit("ERROR: tag key must be non-empty (swagger requires minLength: 1).")
        # Upsert by key.
        return [t for t in current if t.get("tagKey") != key] + [
            {"tagKey": key, "tagValue": value}
        ]

    if action == "rm":
        if len(args) < 1:
            raise SystemExit("ERROR: 'rm' needs <key>")
        key = args[0]
        return [t for t in current if t.get("tagKey") != key]

    if action == "set":
        if len(args) < 1:
            raise SystemExit("ERROR: 'set' needs a JSON array of tag entries")
        try:
            parsed = json.loads(args[0])
        except json.JSONDecodeError as exc:
            raise SystemExit(f"ERROR: 'set' argument is not valid JSON: {exc}")
        if not isinstance(parsed, list):
            raise SystemExit("ERROR: 'set' argument must be a JSON array.")
        return parsed

    if action == "clear":
        return []

    raise SystemExit(f"ERROR: unknown action '{action}'")


def build_edit_body(vpg: dict, new_tags: list[dict]) -> dict:
    """Transform a GET response into an EditVpgRequest body.

    Three blocks are copied verbatim; `general` is stripped of immutable
    region/account fields. `recovery.default.tags` is replaced with new_tags.
    """
    info = vpg["vpgInfo"]
    general = info["general"]
    new_recovery = json.loads(json.dumps(info["recovery"]))  # deep copy
    new_recovery.setdefault("default", {})["tags"] = new_tags
    return {
        "vpg": {
            "general": {
                "name":        general.get("name"),
                "description": general.get("description"),
            },
            "protectedResources": info["protectedResources"],
            "replication":        info["replication"],
            "recovery":           new_recovery,
        }
    }


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("vpg_name")
    parser.add_argument("action", nargs="?", default="show",
                        choices=["show", "add", "rm", "set", "clear"])
    parser.add_argument("args", nargs="*")
    parser.add_argument("-h", "--help", action="store_true")
    a = parser.parse_args()

    if a.help:
        print(__doc__)
        return 0

    host = os.environ["ZIC_HOST"]
    api_base = os.environ.get("ZIC_API_BASE", f"https://{host}/zic/api/v1")
    verify_tls = os.environ.get("ZIC_VERIFY_TLS", "false").lower() in ("1", "true", "yes")

    if not verify_tls:
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    token = get_token()

    # 1) GET — find the VPG by name.
    print(f"→ GET    {api_base}/vpgs")
    vpg = find_vpg_by_name(api_base, token, verify_tls, a.vpg_name)
    vpg_id = vpg.get("vpgId")
    print(f"  resolved vpgId: {vpg_id}\n")

    current_tags = ((vpg.get("vpgInfo") or {}).get("recovery") or {}).get("default", {}).get("tags") or []
    print_tags("Current tags", current_tags)

    if a.action == "show":
        return 0

    # 2) Compute the new tag set.
    new_tags = compute_new_tags(a.action, current_tags, a.args)
    print()
    print_tags("New tags (about to be applied)", new_tags)

    # 3) Build the EditVpgRequest body.
    body = build_edit_body(vpg, new_tags)

    # 4) PUT it back.
    print(f"\n→ PUT    {api_base}/vpgs/{vpg_id}")
    resp = requests.put(
        f"{api_base}/vpgs/{vpg_id}",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        json=body,
        verify=verify_tls,
        timeout=60,
    )
    if resp.status_code != 202:
        print(f"ERROR: expected 202 Accepted, got {resp.status_code}", file=sys.stderr)
        print(f"Response body: {resp.text}", file=sys.stderr)
        return 1
    print("  202 Accepted — update queued")

    # 5) Find the task and follow it.
    print("\n→ following task ...")
    time.sleep(2)
    resp = requests.get(
        f"{api_base}/tasks", params={"top": 1},
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        verify=verify_tls, timeout=30,
    )
    resp.raise_for_status()
    tasks = (resp.json() or {}).get("tasks") or []
    if not tasks:
        print("WARNING: couldn't auto-find the task.", file=sys.stderr)
        return 0
    task_id = (tasks[0].get("taskId") or {}).get("id")

    monitor = Path(__file__).resolve().parents[1] / "07-monitor-task" / "monitor_task.py"
    return subprocess.call([sys.executable, str(monitor), task_id])


if __name__ == "__main__":
    try:
        sys.exit(main())
    except requests.HTTPError as exc:
        print(f"ERROR: HTTP {exc.response.status_code}: {exc.response.text}", file=sys.stderr)
        sys.exit(1)
    except SystemExit:
        raise
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
