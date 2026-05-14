# 11 — Manage member accounts (onboard / update / offboard)  (v2 only)

> **This example requires v2 of the API.** Set `ZIC_API_VERSION=v2`
> in your `.env`, though this script always hits v2 directly
> regardless.

The full CRUD lifecycle for member accounts.

## The endpoints

```
POST   /api/v2/zicconfiguration/memberaccounts                — onboard
PUT    /api/v2/zicconfiguration/memberaccounts/{accountId}    — update
DELETE /api/v2/zicconfiguration/memberaccounts/{accountId}    — offboard
```

All three return on a task model — confirm with `GET /api/v2/tasks/{id}`
(example 07 works against v2 unchanged) and the
`operationType` will be `CreateMemberAccount`, `UpdateMemberAccount`,
or `DeleteMemberAccount`.

## Onboard a new member account

```
POST  /api/v2/zicconfiguration/memberaccounts

Body (CreateMemberAccountRequest):
{
  "accountId":  { "id": "<12-digit-aws-account-id>" },  ← required
  "externalId": "<sts-external-id>",                    ← required
  "description": "Production AWS account"
}
```

Both `accountId` and `externalId` are required (per the schema's
`required: ["accountId", "externalId"]`). Description is optional.

**Pre-requisites in AWS** (the appliance can't do these for you):

1. The target AWS account must have an IAM role that trusts the ZIC
   appliance's principal.
2. The role's trust policy must include the `sts:ExternalId`
   condition matching the value you pass as `externalId`.
3. The role must have the permissions ZIC needs (snapshot, EBS,
   describe-instances, etc.). Refer to the Zerto documentation for
   the current policy template.

If any of those are missing, the account onboards with
`status: NotReady` and `statusDescription` tells you which check
failed.

## Update a member account

```
PUT  /api/v2/zicconfiguration/memberaccounts/{accountId}

Body (UpdateMemberAccountRequest):
{
  "externalId":  "<new-or-same-sts-external-id>",  ← required
  "description": "...",                            ← optional, null to clear
  "cmksPerRegion": [
    { "regionId": { "id": "us-east-1" }, "cmkId": "arn:aws:kms:us-east-1:..." }
  ]
}
```

> **The `accountId` is not in the body** — it goes in the URL path.
> You can't move an account from one AWS ID to another; that would
> be an offboard-and-onboard.

`cmksPerRegion` is fully replaced on each PUT, not patched. Send the
complete list you want present after the update. Empty array means
"use AWS-managed keys for all regions."

## Offboard a member account

```
DELETE  /api/v2/zicconfiguration/memberaccounts/{accountId}
```

Returns a task. The delete will fail if the account still has VPGs
attached to it — clean those up first via example 09 / `DELETE /vpgs/{id}`.

## What this script does

```
./manage-member-accounts.sh add  <accountId> <externalId> [description]
./manage-member-accounts.sh edit <accountId> <externalId> [description]
./manage-member-accounts.sh rm   <accountId>
```

Each mutating action:

1. POSTs/PUTs/DELETEs as appropriate
2. Looks up the resulting task via `GET /api/v2/tasks?top=1`
3. Hands the task off to example 07 to poll until completion

## Error responses

v2 uses **RFC 7807 ProblemDetails** for these endpoints (the older
VPG endpoints still use the legacy `ErrorResponse` — yes, the API
mixes conventions):

```json
{
  "type":     "https://...",
  "title":    "Member account already exists",
  "status":   400,
  "detail":   "Account 123456789012 is already configured.",
  "instance": "/api/v2/zicconfiguration/memberaccounts"
}
```

So when you see a "weird" error response shape on these endpoints,
that's why — different RFC.

## Run it

```bash
# Onboard
./manage-member-accounts.sh add 123456789012 zerto-trust-xyz "Production"

# Update description
./manage-member-accounts.sh edit 123456789012 zerto-trust-xyz "Production (renamed)"

# Offboard
./manage-member-accounts.sh rm 123456789012
```

Same flags for the Python and PowerShell variants.
