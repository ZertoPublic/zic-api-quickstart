#!/usr/bin/env python3
"""Get an OAuth bearer token from the ZIC appliance's Keycloak.

Prints the access_token to stdout on success; non-zero exit on failure.
Other examples in this repo import `get_token()` from here.
"""
from __future__ import annotations

import os
import sys
import urllib3
from pathlib import Path

import requests

# Auto-load ../../.env if it exists.
ENV_FILE = Path(__file__).resolve().parents[2] / ".env"
if ENV_FILE.exists():
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


def get_token() -> str:
    """Authenticate against Keycloak and return the bearer access token."""
    host = os.environ["ZIC_HOST"]
    username = os.environ["ZIC_USERNAME"]
    password = os.environ["ZIC_PASSWORD"]
    token_url = os.environ.get(
        "ZIC_TOKEN_URL",
        f"https://{host}/auth/realms/zerto/protocol/openid-connect/token",
    )
    client_id = os.environ.get("ZIC_CLIENT_ID", "zerto-client")
    verify_tls = os.environ.get("ZIC_VERIFY_TLS", "false").lower() in ("1", "true", "yes")

    if not verify_tls:
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    response = requests.post(
        token_url,
        data={
            "grant_type": "password",
            "scope": "openid",
            "client_id": client_id,
            "username": username,
            "password": password,
        },
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        verify=verify_tls,
        timeout=30,
    )
    response.raise_for_status()

    token = response.json().get("access_token")
    if not token:
        raise RuntimeError(f"no access_token in response: {response.text}")
    return token


if __name__ == "__main__":
    try:
        print(get_token())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
