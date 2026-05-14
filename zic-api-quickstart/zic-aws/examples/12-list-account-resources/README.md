# 12 — List account-scoped resources  (v2 only)

> **This example requires v2 of the API.** All paths start with
> `/api/v2/accounts/{accountId}/...`.

In v1, every AWS resource discovery call (VMs, VPCs, subnets,
security groups, key pairs) was scoped to a region only. v2 scopes
everything to **an account + a region**, which is how multi-account
deployments actually work — the same `us-east-1` can mean different
inventory across different AWS accounts.

v2 also adds three new resource types that v1 didn't expose at all:
**KMS customer-managed keys (CMKs)**, **EC2 launch templates**, and
**IAM roles**.

## All the account-scoped endpoints

```
# Region-scoped (account + region):
GET /api/v2/accounts/{accountId}/regions
GET /api/v2/accounts/{accountId}/regions/{regionId}/resources/vms
GET /api/v2/accounts/{accountId}/regions/{regionId}/resources/vms/{vmId}/nics
GET /api/v2/accounts/{accountId}/regions/{regionId}/resources/vnets
GET /api/v2/accounts/{accountId}/regions/{regionId}/resources/vnets/{vnetId}/subnets
GET /api/v2/accounts/{accountId}/regions/{regionId}/resources/vnets/{vnetId}/sgroups
GET /api/v2/accounts/{accountId}/regions/{regionId}/resources/subnets/{subnetId}
GET /api/v2/accounts/{accountId}/regions/{regionId}/resources/keypairs
GET /api/v2/accounts/{accountId}/regions/{regionId}/resources/cmks            ← new in v2
GET /api/v2/accounts/{accountId}/regions/{regionId}/resources/launchtemplates ← new in v2

# Account-scoped (no region):
GET /api/v2/accounts/{accountId}/resources/roles                              ← new in v2
```

## The three new resource types

### CMKs (Customer-Managed Keys)

```
GET /api/v2/accounts/{accountId}/regions/{regionId}/resources/cmks
```

Returns `CmksResponse` with a list of `CustomerManagedKeyModel`.
Use these when configuring a member account's `cmksPerRegion` (see
example 11) — ZIC will use the specified KMS key to encrypt the EBS
snapshots and recovery volumes it creates in that region.

### Launch Templates

```
GET /api/v2/accounts/{accountId}/regions/{regionId}/resources/launchtemplates
```

Returns:

```json
{
  "launchTemplates": [
    { "id": "lt-0abc123...", "name": "prod-web-template" }
  ]
}
```

Pre-existing EC2 launch templates you can plug into a VPG's
`recovery.default.launchTemplate.failover.launchTemplateId` (or the
`failoverTest` variant). Useful when you want recovery VMs to
inherit a specific AMI, user-data script, or instance profile from
an existing template rather than spelling out each property in the
VPG body.

### IAM Roles (account-scoped, not region-scoped)

```
GET /api/v2/accounts/{accountId}/resources/roles
```

Note this one's scoped to the account only — IAM roles aren't
regional. Returns:

```json
{ "roles": [ { "name": "ZertoRecoveryRole" } ] }
```

Use the role name in `recovery.default.role.roleName` (or per-VM
override) to set the IAM instance profile on the recovered EC2
instances.

## What this script does

A small CLI for each of the v2 discovery endpoints, scoped to one
account at a time:

```
./list-account-resources.sh <accountId> regions
./list-account-resources.sh <accountId> vms          <regionId> [tagName tagValue]
./list-account-resources.sh <accountId> vnets        <regionId>
./list-account-resources.sh <accountId> subnets      <regionId> <vnetId>
./list-account-resources.sh <accountId> sgroups      <regionId> <vnetId>
./list-account-resources.sh <accountId> keypairs     <regionId>
./list-account-resources.sh <accountId> cmks         <regionId>
./list-account-resources.sh <accountId> launchtemplates <regionId>
./list-account-resources.sh <accountId> roles
```

Same flags for `list_account_resources.py` (positional args). The
PowerShell variant takes `-AccountId`, `-Resource`, `-RegionId`,
`-VnetId`.

## How this changes example 04's usefulness

Example 04 (`list-vms-in-region`) was written against v1's
`/regions/{regionId}/resources/vms`. That endpoint **doesn't exist
in v2** — it's been replaced by
`/accounts/{accountId}/regions/{regionId}/resources/vms`.

If you flip `ZIC_API_VERSION=v2` in your `.env`, example 04 will get
a 404. The v2 equivalent is `./list-account-resources.sh <accountId>
vms <regionId>`. The underlying response schema is the same; only
the URL changed.

## How VPG creation differs in a multi-account setup

The VPG body itself is identical between v1 and v2 — same
`CreateVpgRequest`, same nested `general.protectedAccount` /
`general.recoveryAccount` slots, same TimeSpan strings for RPO.

What changes is **the workflow before you POST**:

1. Example 10 — pick the source and destination member accounts
2. This example — list VMs/subnets/sgroups in each, scoped per account
3. Example 06 — POST the VPG body with the right `accountId.id`
   values plugged in

Same schema, real meaning behind the previously-decorative
`protectedAccount`/`recoveryAccount` fields.

## Run it

```bash
# List the regions enabled for account 123456789012
./list-account-resources.sh 123456789012 regions

# List VMs in that account's us-east-1
./list-account-resources.sh 123456789012 vms us-east-1

# List launch templates
./list-account-resources.sh 123456789012 launchtemplates us-east-1

# List IAM roles (account-scoped, no region)
./list-account-resources.sh 123456789012 roles
```
