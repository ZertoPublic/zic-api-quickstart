#!/usr/bin/env python3
"""List active (non-dismissed) alerts on the ZIC appliance."""
from __future__ import annotations

import os
import sys
from pathlib import Path

import urllib3
import requests

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "01-get-token"))
from get_token import get_token  # type: ignore  # noqa: E402


def main() -> int:
    host = os.environ["ZIC_HOST"]
    api_base = os.environ.get("ZIC_API_BASE", f"https://{host}/zic/api/v1")
    verify_tls = os.environ.get("ZIC_VERIFY_TLS", "false").lower() in ("1", "true", "yes")

    if not verify_tls:
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    token = get_token()
    resp = requests.get(
        f"{api_base}/alerts",
        params={"isDismissed": "false"},
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        verify=verify_tls,
        timeout=30,
    )
    resp.raise_for_status()

    alerts = (resp.json() or {}).get("alerts") or []
    if not alerts:
        print("No active alerts.")
        return 0

    print(f"{len(alerts)} active alert(s):\n")
    for a in alerts:
        key = a.get("alertKey") or {}
        ftype = key.get("failureType", "?")
        entity = a.get("alertEntity", "?")
        level = a.get("alertLevel", "?")
        helpid = a.get("alertHelpId", "?")
        print(f"[{level}]  {helpid}  ({entity}/{ftype})")
        print(f"        startTime: {a.get('startTime', '?')}")
        print(f"        vpgId:     {a.get('vpgId') or '-'}")
        print(f"        {a.get('alertDescription', '')}\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
