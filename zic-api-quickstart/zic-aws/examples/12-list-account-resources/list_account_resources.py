#!/usr/bin/env python3
"""Multiplexing CLI for v2's account-scoped resource discovery endpoints.

Usage:
    python3 list_account_resources.py <accountId> regions
    python3 list_account_resources.py <accountId> vms          <regionId> [tagName tagValue]
    python3 list_account_resources.py <accountId> vnets        <regionId>
    python3 list_account_resources.py <accountId> subnets      <regionId> <vnetId>
    python3 list_account_resources.py <accountId> sgroups      <regionId> <vnetId>
    python3 list_account_resources.py <accountId> keypairs     <regionId>
    python3 list_account_resources.py <accountId> cmks         <regionId>
    python3 list_account_resources.py <accountId> launchtemplates <regionId>
    python3 list_account_resources.py <accountId> roles
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import urllib3
import requests

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "01-get-token"))
from get_token import get_token  # type: ignore  # noqa: E402


def build_url(v2_base: str, account_id: str, resource: str, args: list[str]) -> str:
    base = f"{v2_base}/accounts/{account_id}"
    if resource == "regions":
        return f"{base}/regions"
    if resource == "vms":
        if len(args) < 1:
            raise SystemExit("ERROR: vms requires <regionId>")
        url = f"{base}/regions/{args[0]}/resources/vms"
        if len(args) >= 3:
            url += f"?tagName={args[1]}&tagValue={args[2]}"
        return url
    if resource == "vnets":
        if len(args) < 1:
            raise SystemExit("ERROR: vnets requires <regionId>")
        return f"{base}/regions/{args[0]}/resources/vnets"
    if resource == "subnets":
        if len(args) < 2:
            raise SystemExit("ERROR: subnets requires <regionId> <vnetId>")
        return f"{base}/regions/{args[0]}/resources/vnets/{args[1]}/subnets"
    if resource == "sgroups":
        if len(args) < 2:
            raise SystemExit("ERROR: sgroups requires <regionId> <vnetId>")
        return f"{base}/regions/{args[0]}/resources/vnets/{args[1]}/sgroups"
    if resource == "keypairs":
        if len(args) < 1:
            raise SystemExit("ERROR: keypairs requires <regionId>")
        return f"{base}/regions/{args[0]}/resources/keypairs"
    if resource == "cmks":
        if len(args) < 1:
            raise SystemExit("ERROR: cmks requires <regionId>")
        return f"{base}/regions/{args[0]}/resources/cmks"
    if resource == "launchtemplates":
        if len(args) < 1:
            raise SystemExit("ERROR: launchtemplates requires <regionId>")
        return f"{base}/regions/{args[0]}/resources/launchtemplates"
    if resource == "roles":
        return f"{base}/resources/roles"
    raise SystemExit(f"ERROR: unknown resource '{resource}'")


def print_summary(resource: str, payload: dict) -> None:
    """Best-effort summary; falls back to pretty JSON if the shape is unfamiliar."""
    formatters = {
        "regions":         (lambda p: p.get("regions"),         lambda x: f"  {x.get('id','?'):<16}  {x.get('name','-')}"),
        "vms":             (lambda p: p.get("vms"),             lambda x: f"  {(x.get('vmPropertiesModel') or {}).get('id','?'):<22}  {(x.get('vmPropertiesModel') or {}).get('name','-'):<25}  protected={(x.get('additionalPropertiesModel') or {}).get('isProtected', False)}"),
        "vnets":           (lambda p: p.get("vnets"),           lambda x: f"  {x.get('id', x.get('vnetId','?')):<22}  {x.get('name','-')}"),
        "subnets":         (lambda p: p.get("subnets"),         lambda x: f"  {x.get('id', x.get('subnetId','?')):<22}  {x.get('name','-'):<20}  {x.get('availabilityZone','-')}"),
        "sgroups":         (lambda p: p.get("sgroups"),         lambda x: f"  {x.get('id','?'):<22}  {x.get('name','-')}"),
        "keypairs":        (lambda p: p.get("keypairs"),        lambda x: f"  {x.get('name','?')}"),
        "cmks":            (lambda p: p.get("cmks"),            lambda x: f"  {x.get('id', x.get('cmkId', x.get('arn','?'))):<60}  {x.get('alias', x.get('name','-'))}"),
        "launchtemplates": (lambda p: p.get("launchTemplates"), lambda x: f"  {x.get('id','?'):<24}  {x.get('name','-')}"),
        "roles":           (lambda p: p.get("roles"),           lambda x: f"  {x.get('name','?')}"),
    }
    extract, fmt = formatters.get(resource, (None, None))
    items = extract(payload) if extract else None
    if items is None:
        print(json.dumps(payload, indent=2))
        return
    if not items:
        print(f"(no {resource} returned)")
        return
    for item in items:
        print(fmt(item))


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    account_id = sys.argv[1]
    resource = sys.argv[2]
    args = sys.argv[3:]

    host = os.environ["ZIC_HOST"]
    v2_base = f"https://{host}/zic/api/v2"
    verify_tls = os.environ.get("ZIC_VERIFY_TLS", "false").lower() in ("1", "true", "yes")

    if not verify_tls:
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    url = build_url(v2_base, account_id, resource, args)
    token = get_token()

    print(f"→ GET    {url}")
    resp = requests.get(
        url,
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        verify=verify_tls,
        timeout=30,
    )
    resp.raise_for_status()
    print_summary(resource, resp.json() or {})
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except requests.HTTPError as exc:
        print(f"ERROR: HTTP {exc.response.status_code}: {exc.response.text}", file=sys.stderr)
        sys.exit(1)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
