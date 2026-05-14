#!/usr/bin/env python3
"""List AWS regions the ZIC appliance is enabled for."""
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
        f"{api_base}/regions",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        verify=verify_tls,
        timeout=30,
    )
    resp.raise_for_status()
    regions = (resp.json() or {}).get("regions") or []

    if not regions:
        print("(no regions enabled on this appliance)")
        return 0

    print(f"{len(regions)} region(s) enabled:\n")
    print(f"{'id':<16} | name")
    print(f"{'-' * 16}-+-{'-' * 34}")
    for r in regions:
        print(f"{(r.get('id') or '?'):<16} | {r.get('name') or '?'}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
