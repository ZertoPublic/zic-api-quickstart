# 10 — List member accounts  (v2 only)

> **This example requires v2 of the API.** It hits
> `/api/v2/zicconfiguration/memberaccounts`, which doesn't exist on
> v1. Set `ZIC_API_VERSION=v2` in your `.env` before running.

A **member account** is an AWS account the ZIC appliance has been
authorized to protect or recover into. In a single-account
deployment there's typically one (the appliance's own AWS account).
In a multi-account deployment, this list is where you discover the
other AWS accounts that have a cross-account IAM trust set up with
the ZIC appliance.

## The endpoint

```
GET  https://<zic-host>/zic/api/v2/zicconfiguration/memberaccounts
     Authorization: Bearer <token>
```

Response (`MemberAccountsResponse`):

```json
{
  "accounts": [
    {
      "accountId":  { "id": "123456789012" },
      "description": "Production AWS account",
      "externalId":  "zerto-trust-...",
      "cmksPerRegion": [
        { "regionId": { "id": "us-east-1" }, "cmkId": "arn:aws:kms:..." }
      ],
      "status":            "Ready",
      "statusDescription": null
    }
  ]
}
```

Fields worth knowing:

| Field | What it is |
| ----- | ---------- |
| `accountId.id` | The AWS account number (12 digits). Plug this into v2's account-scoped resource endpoints (`/api/v2/accounts/{accountId}/...`) and into `protectedAccount`/`recoveryAccount` in VPG configs. |
| `description` | Free-text label; what you see in the UI. |
| `externalId` | The AWS STS external ID baked into the IAM trust relationship between this member account and the ZIC appliance's role. Required for the assume-role hop to work. |
| `cmksPerRegion` | Customer-managed KMS keys configured per region for this account, used to encrypt the snapshots/EBS volumes ZIC creates. Empty array = use AWS-managed keys. |
| `status` | `Ready` or `NotReady`. NotReady usually means the IAM trust is broken or the external ID drifted. |
| `statusDescription` | Populated when `status != Ready` — read this for the human-readable reason. |

## Usage statistics

A sibling endpoint gives you per-account usage at a glance:

```
GET  /api/v2/zicconfiguration/memberaccounts/statistics
```

Response (`MemberAccountsStatisticResponse`):

```json
{
  "accounts": [
    { "accountId": { "id": "123456789012" }, "protectedVms": 47, "totalVpgs": 8 }
  ]
}
```

Useful for license-quota dashboards and capacity-planning rollups
without joining `/vpgs` + `/regions/{id}/resources/vms` by hand.

## Run it

```bash
./list-member-accounts.sh                # accounts only
./list-member-accounts.sh --stats        # also fetch /statistics

python3 list_member_accounts.py
python3 list_member_accounts.py --stats

./List-MemberAccounts.ps1
./List-MemberAccounts.ps1 -Stats
```

## Adjacent endpoints (see example 11)

- `POST   /api/v2/zicconfiguration/memberaccounts`             — onboard a new member account
- `PUT    /api/v2/zicconfiguration/memberaccounts/{accountId}` — update description, external ID, or CMKs
- `DELETE /api/v2/zicconfiguration/memberaccounts/{accountId}` — offboard

## Why this matters for v2

Once you have multiple member accounts, every other v2 endpoint
takes an `accountId` path parameter. Examples 12 (account-scoped
resource discovery) and 06 (VPG creation, when used with v2) both
depend on knowing the account IDs from this list.
