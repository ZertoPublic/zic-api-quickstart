#!/usr/bin/env python3
"""List member accounts on a ZIC v2 appliance.

Usage:
    python3 list_member_accounts.py
    python3 list_member_accounts.py --stats
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import urllib3
import requests

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "01-get-token"))
from get_token import get_token  # type: ignore  # noqa: E402


def main(with_stats: bool) -> int:
    host = os.environ["ZIC_HOST"]
    # v2-only example — build v2 URL regardless of ZIC_API_BASE.
    v2_base = f"https://{host}/zic/api/v2"
    verify_tls = os.environ.get("ZIC_VERIFY_TLS", "false").lower() in ("1", "true", "yes")

    if not verify_tls:
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    token = get_token()
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}

    print(f"→ GET    {v2_base}/zicconfiguration/memberaccounts")
    resp = requests.get(
        f"{v2_base}/zicconfiguration/memberaccounts",
        headers=headers, verify=verify_tls, timeout=30,
    )
    resp.raise_for_status()
    accounts = (resp.json() or {}).get("accounts") or []

    if not accounts:
        print("(no member accounts configured)")
        return 0

    print(f"  {len(accounts)} member account(s):\n")
    for a in accounts:
        aid = (a.get("accountId") or {}).get("id", "?")
        desc = a.get("description") or "-"
        status = a.get("status", "?")
        status_desc = a.get("statusDescription")
        ext_id = a.get("externalId") or "-"
        cmk_count = len(a.get("cmksPerRegion") or [])
        status_line = status + (f"  — {status_desc}" if status_desc else "")
        print(f"  accountId: {aid}")
        print(f"    description:    {desc}")
        print(f"    status:         {status_line}")
        print(f"    externalId:     {ext_id}")
        print(f"    cmksPerRegion:  {cmk_count} configured")
        print()

    if with_stats:
        print(f"→ GET    {v2_base}/zicconfiguration/memberaccounts/statistics")
        resp = requests.get(
            f"{v2_base}/zicconfiguration/memberaccounts/statistics",
            headers=headers, verify=verify_tls, timeout=30,
        )
        resp.raise_for_status()
        stats = (resp.json() or {}).get("accounts") or []
        print()
        print(f"  {'accountId':<15} | {'protectedVms':<13} | {'totalVpgs':<9}")
        print(f"  {'-'*15}-+-{'-'*13}-+-{'-'*9}")
        for s in stats:
            aid = (s.get("accountId") or {}).get("id", "?")
            pvms = s.get("protectedVms", 0)
            vpgs = s.get("totalVpgs", 0)
            print(f"  {aid:<15} | {pvms:<13} | {vpgs:<9}")
    return 0


if __name__ == "__main__":
    with_stats = "--stats" in sys.argv[1:]
    try:
        sys.exit(main(with_stats))
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
