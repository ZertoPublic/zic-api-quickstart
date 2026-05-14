#!/usr/bin/env python3
"""List every VPG on the ZIC appliance."""
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
        f"{api_base}/vpgs",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        verify=verify_tls,
        timeout=30,
    )
    resp.raise_for_status()
    payload = resp.json()

    vpgs = payload.get("vpgs") or []
    degraded = payload.get("vpgsWithoutData") or []

    if not vpgs and not degraded:
        print("(no VPGs on this appliance)")
        return 0

    print(f"{'Name':<26} | {'vpgState':<22} | {'protectionStatus':<22} | {'actualRpo':<12} | VMs")
    print(f"{'-'*26}-+-{'-'*22}-+-{'-'*22}-+-{'-'*12}-+-{'-'*3}")
    for vpg in vpgs:
        info = vpg.get("vpgInfo") or {}
        gen = info.get("general") or {}
        prot = info.get("protectedResources") or {}
        rep = (vpg.get("replicationInfo") or {}).get("replicationStatistics") or {}
        name = gen.get("name") or "?"
        state = vpg.get("vpgState") or "?"
        pstatus = rep.get("protectionStatus") or "?"
        rpo = rep.get("actualRpo") or "?"
        vms = len(prot.get("vms") or [])
        print(f"{name:<26} | {state:<22} | {pstatus:<22} | {rpo:<12} | {vms}")

    if degraded:
        print()
        print(f"⚠ {len(degraded)} VPG(s) returned without full data (vpgsWithoutData).")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
