#!/usr/bin/env python3
"""List EC2 VMs in a ZIC-enabled region.

Usage:  python3 list_vms_in_region.py <regionId> [tagName tagValue]
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import urllib3
import requests

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "01-get-token"))
from get_token import get_token  # type: ignore  # noqa: E402


def main(region: str, tag_name: str | None, tag_value: str | None) -> int:
    host = os.environ["ZIC_HOST"]
    api_base = os.environ.get("ZIC_API_BASE", f"https://{host}/zic/api/v1")
    verify_tls = os.environ.get("ZIC_VERIFY_TLS", "false").lower() in ("1", "true", "yes")

    if not verify_tls:
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    token = get_token()
    params = {}
    if tag_name and tag_value:
        params = {"tagName": tag_name, "tagValue": tag_value}

    resp = requests.get(
        f"{api_base}/regions/{region}/resources/vms",
        params=params,
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        verify=verify_tls,
        timeout=30,
    )
    resp.raise_for_status()

    vms = (resp.json() or {}).get("vms") or []
    if not vms:
        print(f"(no VMs in region {region})")
        return 0

    print(f"Region: {region}  ({len(vms)} VMs)\n")
    print(f"{'vmId':<22} | {'name':<25} | {'protected':<9} | protectedInVpgs")
    print(f"{'-' * 22}-+-{'-' * 25}-+-{'-' * 9}-+-{'-' * 22}")
    for vm in vms:
        props = vm.get("vmPropertiesModel") or {}
        extra = vm.get("additionalPropertiesModel") or {}
        vmid = props.get("id") or props.get("vmId") or "?"
        name = props.get("name") or props.get("vmName") or "?"
        prot = extra.get("isProtected", False)
        vpgs = ",".join((v or {}).get("id", "") for v in (extra.get("protectedInVpgs") or [])) or "-"
        print(f"{vmid:<22} | {name:<25} | {str(prot):<9} | {vpgs}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: list_vms_in_region.py <regionId> [tagName tagValue]", file=sys.stderr)
        sys.exit(2)
    region = sys.argv[1]
    tag_name = sys.argv[2] if len(sys.argv) > 2 else None
    tag_value = sys.argv[3] if len(sys.argv) > 3 else None
    try:
        sys.exit(main(region, tag_name, tag_value))
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
