# 06 — Create a VPG (one-shot)

The first script that **writes** to the appliance. Read this README
carefully before running anything.

## The pattern

VPG creation in ZIC is a single call, unlike ZVM/ZCA's two-step
settings-then-commit dance:

```
POST  https://<zic-host>/zic/api/v1/vpgs
      Content-Type: application/json
      Authorization: Bearer <token>

      { "vpg": { ...full configuration... } }

→ 202 Accepted (no body)
```

The 202 response **has no body** — meaning no task ID comes back
directly. To monitor the work, you query the tasks list for the
most recent `CreateVpg` task right after the POST. The example
script does this for you.

## The body shape

The request schema is `CreateVpgRequest` → `CreateVpgConfigurationModel`
with four top-level blocks. Verified against the swagger:

```json
{
  "vpg": {
    "general": {
      "name":             "web-tier-dr",
      "description":      "Production web tier DR",
      "protectedRegion":  { "id": "us-east-1" },
      "protectedAccount": { "id": "<member-account-id>" },
      "recoveryRegion":   { "id": "us-west-2" },
      "recoveryAccount":  { "id": "<member-account-id>" }
    },
    "protectedResources": {
      "vms": [
        { "id": "i-0abc123def456789" }
      ]
    },
    "replication": {
      "sla": {
        "rpo":      "00:05:00",
        "rpoAlert": "00:10:00",
        "history":  "1.00:00:00"
      }
    },
    "recovery": {
      "default": {
        "network": {
          "failover": {
            "useDefaultNetwork":  false,
            "failoverNetwork": {
              "virtualNetwork":  { "id": "vpc-0abc..." },
              "subnet":          { "id": "subnet-0abc..." },
              "securityGroups":  [ { "id": "sg-0abc..." } ]
            }
          },
          "failoverTest": {
            "useDefaultNetwork":  false,
            "failoverNetwork": {
              "virtualNetwork":  { "id": "vpc-0abc..." },
              "subnet":          { "id": "subnet-0def..." },
              "securityGroups":  [ { "id": "sg-0abc..." } ]
            }
          }
        },
        "keyPair":  { "keyName": "my-keypair" },
        "role":     { "roleName": null },
        "tags":     [],
        "launchTemplate": {
          "failover":     { "launchTemplateId": null },
          "failoverTest": { "launchTemplateId": null }
        }
      },
      "vms": []
    }
  }
}
```

## The duration format trap

`rpo`, `rpoAlert`, and `history` are .NET **TimeSpan strings**, not
integers. The format is `"[d.]hh:mm:ss"`:

| TimeSpan | Means |
| -------- | ----- |
| `"00:00:30"` | 30 seconds |
| `"00:05:00"` | 5 minutes |
| `"01:00:00"` | 1 hour |
| `"1.00:00:00"` | 1 day |
| `"7.00:00:00"` | 7 days (typical history target) |

Passing `300` (an integer) for the RPO will fail validation with
`InvalidCreateVpgRequest`.

## Tags on the recovery VMs

`recovery.default.tags` is an array of `FailoverDefaultTagModel`
entries. From the swagger: *"The default tag will be assigned to all
the recovery VMs of the VPG during recovery operations."*

These tags get applied to the EC2 instances that ZIC spins up in the
recovery region during a failover or failover-test — not to the VPG
configuration itself, and not to the source VMs. AWS tags on the
source instances are read-only (use them to filter via example 04's
`tagName`/`tagValue` query params); these are the tags ZIC will
*write* on the new instances at recovery time.

A populated `tags` block looks like:

```json
"tags": [
  { "tagKey": "Environment",  "tagValue": "DR-failover" },
  { "tagKey": "CostCenter",   "tagValue": "ops-dr" },
  { "tagKey": "ManagedBy",    "tagValue": "Zerto-ZIC" },
  { "tagKey": "SourceVpg",    "tagValue": "web-tier-prod" }
]
```

A few constraints worth knowing, taken straight from the swagger:

- Both `tagKey` and `tagValue` are **required** on every entry —
  the swagger marks `tagKey` with `minLength: 1`, so an empty key
  rejects with `InvalidCreateVpgRequest`. An empty *value* is
  technically allowed by the schema but AWS itself accepts empty
  tag values, so behavior should be uniform.
- The full array can be empty (`"tags": []`) — that's the
  default in the body template.
- AWS itself enforces the usual EC2 tag limits: 50 tags per
  resource, 128-char keys, 256-char values, no leading `aws:`
  prefix. ZIC just forwards them.
- There is **no separate endpoint** to tag a VPG itself, and no
  `PUT /vpgs/{id}/tags` to add tags after creation — you set
  `recovery.default.tags` in the create body (or update it later
  via `PUT /api/v1/vpgs/{vpgId}` with an `EditVpgRequest`).

Useful tag patterns:

| Pattern | Why |
| ------- | --- |
| `Environment=DR-failover` | Lets cost dashboards separate steady-state from failover-event spend. |
| `CostCenter=<team>` | Carries cost allocation across the failover boundary so DR EC2 hours bill back correctly. |
| `ManagedBy=Zerto-ZIC` | Marks instances ZIC owns, so AWS-native automation (auto-shutdown, compliance scanners) can exempt them. |
| `SourceVpg=<vpg-name>` | Trail-of-breadcrumbs back to the VPG that recovered the instance — useful when you have several VPGs failing over together. |

## Default vs. per-VM recovery

- **`recovery.default`** is the baseline applied to every VM in the
  VPG: which subnet they land in, which security groups, which IAM
  role, which key pair, which launch template.
- **`recovery.vms`** is an array of per-VM overrides — *only* include
  a VM here if you need to customize something different from the
  default for that one VM. Each entry has shape:
  ```json
  {
    "protectedVm": { "id": "i-0abc..." },
    "keyPair":     { "keyName": "alt-key" },
    "network":     { ...same shape as default.network... },
    "nics":        [ ... per-NIC config ... ],
    "role":        { "roleName": "alt-role" },
    "launchTemplate": { "failover": { "launchTemplateId": "lt-0abc..." }, ... }
  }
  ```
  You don't have to specify every field — anything you omit falls
  back to the default.

## What can go wrong

The swagger defines a precise set of error codes for VPG creation
failures (see `ErrorCodeModel`):

| Error code | Meaning |
| ---------- | ------- |
| `InvalidCreateVpgRequest` | Body shape problem. Check field names, types, and TimeSpan strings. |
| `InvalidRegionIdentifier` | A region ID isn't enabled on the appliance — re-run example 03 to see what is. |
| `PlatformGeneralError` | ZIC tried the AWS call and got something back it didn't expect. |
| `PlatformNoPermissionsError` | The appliance's IAM role can't see / act on the resources you referenced. |
| `RequestValidationError` | A required field is missing or a constraint is violated (e.g. duplicate name). |
| `LicenseVmLimitReached` | This VPG would push you past your licensed VM count. |
| `LicenseValidationError` | License check failed. |
| `VpgManagementTaskIsAlreadyRunning` | A `CreateVpg`/`UpdateVpg`/`DeleteVpg` task is already in flight for one of these VPGs — wait, retry. |

The error response shape is:

```json
{ "errorCode": "InvalidRegionIdentifier", "errorMessage": "Region 'us-east-99' is not enabled..." }
```

Read both fields — `errorCode` is for routing, `errorMessage` is
for humans.

## What this script does

1. Reads `default-vpg-body.json` from this folder.
2. Refuses to run if it still contains `REPLACE_ME` placeholders.
3. POSTs to `/api/v1/vpgs`.
4. On 202, queries `/api/v1/tasks?topPerProperty=VpgId&top=1` to
   find the just-created task.
5. Prints the task ID and a hint to run example 07 to follow it.

## Run it

This folder ships two body templates:

| File | What it has | When to use it |
| ---- | ----------- | -------------- |
| `default-vpg-body.json` | Minimal body, `tags: []` | Most cases — clean baseline to fill in. |
| `example-with-tags.json` | Same body + populated `recovery.default.tags` | When you want the recovery VMs tagged at failover time (cost allocation, DR markers, etc.). |

Pick whichever, edit the `REPLACE_ME_*` placeholders, then run:

```bash
# 1. Edit the body first — every REPLACE_ME has to be a real ID
$EDITOR default-vpg-body.json          # or example-with-tags.json

# 2. Then run (defaults to default-vpg-body.json)
./create-vpg.sh
python3 create_vpg.py
./Create-Vpg.ps1

# Or pass an explicit body
./create-vpg.sh ./example-with-tags.json
python3 create_vpg.py ./example-with-tags.json
./Create-Vpg.ps1 -BodyPath ./example-with-tags.json
```

> **Don't put a `_comment_` key in the body.** `CreateVpgRequest`
> sets `additionalProperties: false`, which means anything outside
> the documented schema — including a `_comment_` field — gets the
> request rejected with `InvalidCreateVpgRequest`. Keep notes in
> the README, not in the JSON.

## Adjacent endpoints

- `PUT    /api/v1/vpgs/{vpgId}` — `EditVpgRequest`, modify a VPG.
- `DELETE /api/v1/vpgs/{vpgId}` — delete a VPG.
- `GET    /api/v1/vpgs/{vpgId}/checkpoints` — list checkpoints
  (recovery points) for a VPG.
- `POST   /api/v1/vpgs/{vpgId}/checkpoints` — manually insert a
  tagged checkpoint.
