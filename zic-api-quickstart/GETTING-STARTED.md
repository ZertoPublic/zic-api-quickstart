# Getting started with the Zerto In-Cloud REST API

A walkthrough for AWS administrators and backup admins who haven't
done much REST API work before. By the end you'll have called the ZIC
API, read your VPGs and alerts, created a VPG, watched the task
finish, and kicked off a non-disruptive failover test. About 20
minutes if you read straight through.

This document is the slow, narrated tour. Each section has a short
"now go run this" pointer to a numbered folder under
[`zic-aws/examples/`](zic-aws/examples) with ready-to-run scripts.
The per-example READMEs are the reference; this one is the **story**.

---

## How the ZIC API is shaped

All endpoints live under `https://<zic-host>/zic/api/v1/...` or
`https://<zic-host>/zic/api/v2/...`. The appliance also serves the
interactive Swagger UI at
`https://<zic-host>/zic/api/help/index.html` — that's the
authoritative reference for everything in this guide.

### Two API versions — when to use which

ZIC exposes **both v1 and v2 of its REST API side-by-side**. The two
overlap so heavily that the difference reduces to one question:

> *Are you doing multi-AWS-account protection?*

- **No** — single account, ZIC protects workloads inside its own
  AWS account → **v1 is enough.** Steps 1–9 below cover it.
- **Yes** — ZIC's appliance account protects workloads in other AWS
  accounts via cross-account IAM trusts → **use v2.** Same eight
  steps below, but flip `ZIC_API_VERSION=v2` in your `.env`, then
  add steps 10–12 for the member-account management surface that
  only v2 exposes.

Why this works: every v1 endpoint has an identical-shape twin in v2
— same request bodies, same response schemas, same task model. Only
the URL prefix differs (`/api/v1` vs `/api/v2`) plus v2 adds a few
new endpoints for member-account CRUD and account-scoped resource
discovery. The bulk of this guide (steps 1–9) is version-agnostic;
the new steps 10–12 are v2-only.

### The endpoint surface

v1 exposes 22 endpoints; v2 exposes 28 (the 22 from v1 plus 6 new
multi-account endpoints). Both organize their endpoints into tags:

| Tag | What it covers | Present in |
| --- | -------------- | ---------- |
| `Vpg` | List, create, update, delete VPGs. | v1 + v2 |
| `Replication` | Checkpoints (recovery points). | v1 + v2 |
| `Recovery` | Failover, failover test, commit, rollback. | v1 + v2 |
| `Resources` (v1) / `AccountResources` (v2) | Read AWS inventory (regions, VPCs, subnets, VMs, NICs, security groups, key pairs — plus CMKs / launch templates / IAM roles on v2). | v1 region-scoped, v2 account+region-scoped |
| `Task` | List and inspect asynchronous task records. | v1 + v2 |
| `Alerts` | List, dismiss, and undismiss alerts. | v1 + v2 |
| `ScaleAccounts` | Legacy cross-account scale accounts. | v1 + v2 |
| `MemberAccounts` | Multi-account onboarding/management. | **v2 only** |
| `ZicConfiguration` / `License` / `Versions` | Appliance configuration, licensing, and version info. | v1 + v2 |

You make calls in roughly four shapes:

| Method | What it means | Example |
| ------ | ------------- | ------- |
| `GET` | "Read me this" | `GET /api/v1/vpgs` returns the VPG list |
| `POST` | "Create this" | `POST /api/v1/vpgs` creates a new VPG |
| `PUT` | "Update / act on this" | `PUT /api/v1/vpgs/{id}/failover` runs a recovery |
| `DELETE` | "Remove this" | `DELETE /api/v1/vpgs/{id}` deletes a VPG |

> **A note for ZVM/ZCA users.** Three things differ from the
> on-prem/ZCA API you may already know:
>
> 1. The base path is `/zic/api/v1/...`, not `/v1/...`.
> 2. VPG creation is **one-shot** — no `vpgSettings` draft step.
> 3. Recovery is `PUT /vpgs/{id}/failover` with a **`Zic-Action`
>    header** that picks the action verb. ZVM's separate
>    `/FailoverTest` and `/Failover` endpoints don't exist here.

Every call needs to **prove who you are**. That's step 1.

---

## Step 1 — Get a token

> **Now go run:** [`zic-aws/examples/01-get-token`](zic-aws/examples/01-get-token)

In the web UI you sign in once and the browser keeps you signed in.
For the API, the equivalent is asking the appliance: *"Here are my
username and password — give me a token I can hand back to you on
every subsequent call."*

ZIC's appliance runs **Keycloak** internally. The swagger declares
the security scheme as OAuth 2.0 implicit flow with authorization
endpoint `/auth/realms/zerto/protocol/openid-connect/auth` — but for
non-interactive scripting, the password grant on the same realm is
what you want and what every Zerto v10 API client uses:

```
1. POST  https://<zic-host>/auth/realms/zerto/protocol/openid-connect/token
         body: grant_type=password
               scope=openid
               client_id=zerto-client
               username=<user>
               password=<pass>
   →     JSON { "access_token": "eyJhbGciOi...", "expires_in": 60 }

2. GET   https://<zic-host>/zic/api/v1/vpgs
         header: Authorization: Bearer eyJhbGciOi...
   →     the actual data you wanted
```

Two things to know about the token:

- It expires fast — `expires_in` is usually 60 seconds. For short
  scripts, re-authenticate at the start of each run. For long-running
  tools, use the `refresh_token` Keycloak also returned.
- `scope=openid` is **required**. Without it, Keycloak issues a token
  but `/api/v1/*` rejects it.

**What success looks like:** the script prints a long string of
gibberish (the JWT) to your terminal.

---

## Step 2 — Read your VPGs

> **Now go run:** [`zic-aws/examples/02-list-vpgs`](zic-aws/examples/02-list-vpgs)

`GET /api/v1/vpgs` returns every Virtual Protection Group the
appliance knows about, wrapped in a `VpgsInfoResponse` envelope:

```json
{
  "vpgs": [ { "vpgId": "...", "vpgState": "...", "vpgInfo": { ... }, "replicationInfo": { ... } } ],
  "vpgsWithoutData": [ "..." ]
}
```

The fields you'll actually use:

| Path in JSON | What it is |
| ------------ | ---------- |
| `vpgs[].vpgId` | Stable UUID for the VPG. |
| `vpgs[].vpgState` | One of: `Protecting`, `FailoverBeforeCommit`, `Recovered`, `FailoverTest`, `NeedsConfiguration`. |
| `vpgs[].vpgInfo.general.name` | What you see in the UI. |
| `vpgs[].vpgInfo.general.protectedRegion.name` / `.recoveryRegion.name` | Source and target AWS regions. |
| `vpgs[].replicationInfo.replicationStatistics.protectionStatus` | One of: `Na`, `Initializing`, `MeetingSLA`, `NotMeetingSLA`, `RpoNotMeetingSLA`, `HistoryNotMeetingSLA`, `Recovered`. |
| `vpgs[].replicationInfo.replicationStatistics.actualRpo` | ISO-8601 duration / .NET TimeSpan. |

A healthy environment is mostly `vpgState: Protecting` +
`protectionStatus: MeetingSLA`. Anything else is worth a closer look.

**This is the moment most people stop being scared of the API.** It's
just a list. You ran a command, you got a list of your VPGs back —
everything else is variations on that idea.

---

## Step 3 — Read your regions

> **Now go run:** [`zic-aws/examples/03-list-regions`](zic-aws/examples/03-list-regions)

In ZIC, "where can I recover to?" is answered by AWS regions, not by
a paired-peer-site concept like ZVM has. `GET /api/v1/regions`
returns the regions the appliance has been enabled for:

```json
{ "regions": [ { "id": "us-east-1", "name": "US East (N. Virginia)" } ] }
```

You won't poll this one daily. You read it when you're about to
**create** a VPG, because the VPG body needs region IDs for both the
protected side and the recovery side.

If a region you'd expect is missing, it hasn't been enabled on the
appliance yet — that's a one-time configuration step in the ZIC UI
or via `PUT /api/v1/zicconfiguration`.

---

## Step 4 — Read VMs in a region

> **Now go run:** [`zic-aws/examples/04-list-vms-in-region`](zic-aws/examples/04-list-vms-in-region)

ZIC doesn't have a VRA list endpoint (no host to install on) and it
doesn't expose a dedicated "protected instances" endpoint either.
What it gives you instead is the inventory of every EC2 VM in a
region, with each entry tagged as protected or not.

```
GET /api/v1/regions/{regionId}/resources/vms
GET /api/v1/regions/{regionId}/resources/vms?tagName=Env&tagValue=prod
```

Each `VmModel` in the response has an `additionalPropertiesModel`
block containing:

```json
{
  "isProtected": true,
  "protectedInVpgs": [ { "id": "abcdef12-..." } ]
}
```

So this endpoint serves three jobs at once:

1. **Discovery for new VPGs.** Find the `vmId` of an EC2 instance
   you want to protect.
2. **Verification.** Confirm a VM is or isn't currently protected.
3. **Tag-based automation.** Use `tagName`/`tagValue` query params
   to find every instance tagged `Protect=true` and create VPGs for
   anything that isn't covered yet.

The companion resource endpoints —
`/resources/vnets`, `/resources/vnets/{vnetId}/subnets`,
`/resources/vnets/{vnetId}/sgroups`, `/resources/keypairs`,
`/resources/vms/{vmId}/nics` — return the AWS objects you'll
plug into the VPG body in step 6. Same pattern as the VMs endpoint;
auth header, JSON in, JSON out.

---

## Step 5 — Read your alerts

> **Now go run:** [`zic-aws/examples/05-list-alerts`](zic-aws/examples/05-list-alerts)

`GET /api/v1/alerts` returns every alert the appliance has raised.
Useful query parameters: `isDismissed`, `level`, `vpgIdentifier`,
`startDate`, `endDate`.

Each alert looks like:

```json
{
  "alertKey":         { "failedEntityIdentifier": "...", "failureType": "RPO" },
  "alertEntity":      "VPG",
  "alertLevel":       "Warning",
  "alertDescription": "VPG web-tier is not meeting RPO target",
  "startTime":        "2026-05-14T09:12:43.000Z",
  "alertHelpId":      "ZIC0006",
  "vpgId":            "...",
  "isDismissed":      false,
  "reasons":          "..."
}
```

The fields that matter for automation:

- **`alertHelpId`** — a stable code (e.g. `ZIC0006`) that doesn't
  change across versions. Route on this, never on the description.
- **`alertEntity`** — `ZIC` (the appliance itself) or `VPG` (a
  specific protection group). Lets you separate "the appliance is
  unhealthy" from "this one VPG has a problem."
- **`failureType`** — one of: `RPO`, `History`, `SLA`,
  `NeedsConfig`, `License`, `NoRegionConnectivity`,
  `LicenseIsAboutToReachVmLimit`, `LicenseVmLimitReached`,
  `MemberAccountDbEncryptionFailed`. Useful for triage routing.

To dismiss an alert programmatically, send the `alertKey` block back:

```
PUT /api/v1/alerts/dismiss
{ "failedEntityIdentifier": "...", "failureType": "RPO" }
```

(Yes, you `PUT` rather than `POST`, and the body is the key object,
not just an ID — that's how the swagger defines it.)

---

## Step 6 — Create a VPG (your first write)

> **Now go run:** [`zic-aws/examples/06-create-vpg`](zic-aws/examples/06-create-vpg)

The first endpoint that **changes** something on the appliance.

Unlike ZVM/ZCA, VPG creation in ZIC is **one-shot**:

```
POST /api/v1/vpgs
Body: { "vpg": { ...full configuration... } }
→ 202 Accepted (no body)
```

The whole VPG configuration goes in one request. The response is HTTP
202 with no body — the work is happening asynchronously, and you
have to **find the task** to monitor it. We'll come back to that.

The body shape (`CreateVpgRequest` → `CreateVpgConfigurationModel`)
has four top-level blocks:

```json
{
  "vpg": {
    "general":            { "name", "description", "protectedRegion", "protectedAccount", "recoveryRegion", "recoveryAccount" },
    "protectedResources": { "vms": [ { "id": "<aws-vm-id>" } ] },
    "replication":        { "sla": { "rpo", "rpoAlert", "history" } },
    "recovery":           { "default": { ... }, "vms": [ ... per-VM overrides ... ] }
  }
}
```

A few things you'll bump into the first time:

- **RPO is a date-span string**, not a number of seconds. The swagger
  marks these fields as .NET TimeSpan-format
  (`"hh:mm:ss"` or `"d.hh:mm:ss"`). For a 10-minute RPO, use
  `"00:10:00"`. For a 24-hour history, use `"1.00:00:00"`.
- **All IDs are AWS native.** The `vms`, `subnet`, `virtualNetwork`,
  and `securityGroups` fields take real AWS identifiers
  (`i-...`, `subnet-...`, `vpc-...`, `sg-...`) — get them from the
  `/regions/{id}/resources/...` endpoints in step 4.
- **Default vs. per-VM recovery.** `recovery.default` sets the
  baseline (network, key pair, IAM role, launch template) that
  applies to every VM. `recovery.vms` is an array of per-VM
  overrides — only include a VM here if you need to override a
  default for it.
- **Validation errors are precise.** The error model returns one of
  ~26 specific codes — `InvalidCreateVpgRequest`,
  `InvalidRegionIdentifier`, `PlatformNoPermissionsError`, etc. —
  with a human-readable `errorMessage`. Read both.

When the POST returns 202, the new VPG **does not exist yet**. The
appliance has accepted the request and queued the work. To watch it,
hit `GET /api/v1/tasks?topPerProperty=VpgId&top=1` immediately after
to find the most recent task associated with VPG creation, then
follow it in step 7.

(The 202-no-body pattern means there's no easy way to get the task
ID directly from the create response — you have to look it up. The
example script does this for you.)

---

## Step 7 — Watch a task to completion

> **Now go run:** [`zic-aws/examples/07-monitor-task`](zic-aws/examples/07-monitor-task)

Most writes on the ZIC API are asynchronous — the appliance accepts
your request, queues the work, and tracks it as a **task** you can
poll.

```
GET /api/v1/tasks/{taskId}
```

A `TaskInfoModel` response:

```json
{
  "taskId":          { "id": "8f4a7c2b-..." },
  "startTime":       "2026-05-14T09:12:43Z",
  "endTime":         null,
  "status":          "Running",
  "progress":        45.0,
  "vpgId":           "...",
  "memberAccountId": "...",
  "operationType":   "CreateVpg",
  "taskResult":      { "taskCompletionStatus": null, "failureReason": null }
}
```

The fields that matter:

| Field | Values | What it means |
| ----- | ------ | ------------- |
| `status` | `NotStarted`, `Running`, `RunningCancellationRequested`, `Completed` | The state machine. `Completed` is terminal regardless of success. |
| `taskResult.taskCompletionStatus` | `Success`, `Failed`, `Cancelled`, `PartialSuccess` | Populated only once `status` is `Completed`. **This is how you know whether the work actually succeeded.** |
| `taskResult.failureReason` | string or null | Populated on `Failed`. Includes the AWS-level error when applicable. |
| `operationType` | `CreateVpg`, `UpdateVpg`, `DeleteVpg`, `FailoverLive`, `FailoverTest`, `FailoverTestStop`, `FailoverLiveCommit`, `FailoverLiveRollback`, etc. | Lets you correlate a task back to the operation that started it. |

A polling loop is: sleep 5 seconds, fetch the task, exit when
`status` is `Completed`. Then check `taskResult.taskCompletionStatus`
to decide whether to celebrate or roll back.

To find the task associated with a recent operation when you don't
have the ID, use `GET /api/v1/tasks?top=1` (most recent) or
`?topPerProperty=VpgId&top=1` (most recent per VPG).

---

## Step 8 — Run a non-disruptive failover test

> **Now go run:** [`zic-aws/examples/08-failover-test`](zic-aws/examples/08-failover-test)

Every recovery action — failover, test, commit, rollback — is the
same endpoint:

```
PUT /api/v1/vpgs/{vpgId}/failover
Zic-Action: <one of: failover | failoverCommit | failoverRollback | failoverTest | failoverTestStop>
Body: { "recoveryOperation": { "checkpointId": <int>, "shutdownProtectedVmsOnCommit": false, "reverseProtectVpgOnCommit": false } }
→ 202 Accepted (no body)
```

The verb is in the **header**, not the URL. This is unusual but it
keeps the endpoint surface tight — one route handles all five recovery
operations.

A non-disruptive test flow looks like:

```
1. GET   /api/v1/vpgs/{vpgId}/checkpoints   → pick a checkpoint to test
2. PUT   /api/v1/vpgs/{vpgId}/failover      → Zic-Action: failoverTest
   ... appliance spins up test VMs in the recovery region ...
3. Poll  /api/v1/tasks/{taskId} until Completed/Success
4. ... your team manually validates the test VMs ...
5. PUT   /api/v1/vpgs/{vpgId}/failover      → Zic-Action: failoverTestStop
   ... appliance tears down the test VMs ...
```

The example script in `08-failover-test` does steps 1, 2, 3 and
prints how to run step 5 by hand once you're satisfied.

> ⚠️ **Real failover (`failover` / `failoverCommit` /
> `failoverRollback`) shuts down or replaces production resources.**
> The example deliberately does `failoverTest` only — it's the
> non-disruptive variant. Don't change `Zic-Action` to `failover`
> without understanding what that does to your live workload.

---

## Step 9 — Edit a VPG (read-modify-write)

> **Now go run:** [`zic-aws/examples/09-tag-management`](zic-aws/examples/09-tag-management)

Updating anything on an existing VPG — tags, RPO, recovery subnet,
launch template, per-VM overrides — goes through one endpoint:

```
PUT /api/v1/vpgs/{vpgId}
Body: EditVpgRequest  (a full configuration, NOT a partial)
→ 202 Accepted (no body)
```

Two things make this different from every previous step:

1. **It's a full PUT, not a PATCH.** `UpdateVpgConfigurationModel`
   is declared with `additionalProperties: false` and all four
   sub-blocks (`general`, `protectedResources`, `replication`,
   `recovery`) marked required. Sending three of four rejects with
   `InvalidEditVpgRequest`.
2. **Some fields are immutable.** The PUT-side `general` block is
   typed `UpdateVpgGeneralConfigurationModel`, which only has `name`
   and `description`. You **cannot** change `protectedRegion`,
   `protectedAccount`, `recoveryRegion`, or `recoveryAccount` on an
   existing VPG — those are part of the VPG's identity. To move a
   VPG between regions or accounts, delete and recreate.

The workflow is:

```
1. GET   /api/v1/vpgs                         → find the VPG by name
2. (in memory) modify the field(s) you want
3. PUT   /api/v1/vpgs/{vpgId}                 → send the whole modified config back
4. Poll  /api/v1/tasks/{taskId} until Completed/Success
```

The example uses tags as the change target because they're a
low-risk way to exercise the pattern. Once you have it working for
tags, the same script template handles any other VPG edit — the
only thing that changes is what you mutate between the GET and the
PUT.

---

## Steps 10–12 — Multi-account (v2 only)

The remaining three examples are the parts of the API that only
exist on v2. **Skip these if you're running a single-account
deployment**; the eight steps above are everything you need.

If you've flipped your `.env` to `ZIC_API_VERSION=v2`, the previous
examples keep working transparently — only the URL prefix changes.
What follows is the new ground v2 adds on top.

### Step 10 — List member accounts

> **Now go run:** [`zic-aws/examples/10-list-member-accounts`](zic-aws/examples/10-list-member-accounts)

```
GET /api/v2/zicconfiguration/memberaccounts
GET /api/v2/zicconfiguration/memberaccounts/statistics
```

The list of AWS accounts the appliance has been authorized to
protect or recover into. In a multi-account deployment, this is
where you discover the `accountId` values you'll plug into every
other v2 call. The `/statistics` sibling rolls up
`protectedVms` and `totalVpgs` per account — handy for
license-quota dashboards.

### Step 11 — Onboard / update / offboard member accounts

> **Now go run:** [`zic-aws/examples/11-manage-member-accounts`](zic-aws/examples/11-manage-member-accounts)

```
POST   /api/v2/zicconfiguration/memberaccounts                — onboard
PUT    /api/v2/zicconfiguration/memberaccounts/{accountId}    — update
DELETE /api/v2/zicconfiguration/memberaccounts/{accountId}    — offboard
```

The IAM trust between the appliance's role and the new account's
role has to exist *before* you POST — the API can only register
what AWS has already authorized. Look for `status: NotReady` on
fresh accounts: it almost always means the
`sts:AssumeRole`/`ExternalId` setup on the AWS side isn't done yet,
and the API can't fix that for you.

> **Heads-up on error responses.** v2's member-account endpoints
> return errors as RFC 7807 `ProblemDetails` (a `type`/`title`/
> `status`/`detail`/`instance` shape). The inherited VPG, alerts,
> and task endpoints still return the legacy `ErrorResponse` shape
> (`errorCode` + `errorMessage`) even when called via v2. You'll
> see both in the same automation; just be ready for it.

### Step 12 — Account-scoped resource discovery

> **Now go run:** [`zic-aws/examples/12-list-account-resources`](zic-aws/examples/12-list-account-resources)

```
GET /api/v2/accounts/{accountId}/regions
GET /api/v2/accounts/{accountId}/regions/{regionId}/resources/{vms|vnets|...}
GET /api/v2/accounts/{accountId}/resources/roles
```

The v2 replacements for everything example 04 covered, plus three
new resource types: KMS CMKs, EC2 launch templates, and IAM roles.

What changes for VPG creation under v2: nothing in the body shape.
The `CreateVpgRequest` schema is byte-identical between v1 and v2 —
the `protectedAccount.id` and `recoveryAccount.id` fields existed in
v1 but were effectively decorative because there was only one
account. Under v2 they're meaningful: you fill them in with the IDs
from step 10, and the VPG genuinely lives across two AWS accounts.

> **Note:** example 04 (`list-vms-in-region`) hits v1's
> `/regions/{regionId}/resources/vms`, which does **not** exist on
> v2. If you've flipped to v2, run `./list-account-resources.sh
> <accountId> vms <regionId>` instead. Same response shape, just
> account-scoped.

---

## Where to go from here

Once you've made it through these steps, you've used the API the
way most automation does. If you're on v1, that's steps 1–9; if
you're on v2, you've also seen the multi-account surface in 10–12.
The remaining ZIC endpoints follow identical patterns:

- **Checkpoints**: `GET /api/v1/vpgs/{vpgId}/checkpoints` /
  `POST .../checkpoints` (insert a tagged checkpoint).
- **Configuration**: `GET` / `PUT /api/v1/zicconfiguration`.
- **License**: `GET` / `PUT /api/v1/zicconfiguration/license`.
- **Scale accounts** (cross-account member accounts):
  `GET` / `POST` / `DELETE /api/v1/zicconfiguration/scaleaccounts`.

Open the Swagger UI at
`https://<zic-host>/zic/api/help/index.html`, paste a token, and
you can try every endpoint interactively. The swagger is the source
of truth — when this guide and the swagger disagree, the swagger
wins.

---

## A short list of things that will save you grief

1. **Always include `scope=openid` when fetching the token.** The
   `zerto` realm rejects tokens that don't have it.
2. **Never assume a write call is finished when the 202 comes back.**
   Always find the task. Always check `taskResult.taskCompletionStatus`,
   not just `status` — `Completed` can mean Success, Failed,
   Cancelled, or PartialSuccess.
3. **Durations are TimeSpan strings, not seconds.** RPO of "5
   minutes" is `"00:05:00"`, not `300`.
4. **All resource IDs are AWS-native.** Don't paste Zerto identifiers
   where the API expects an `i-...` or `subnet-...`.
5. **The Swagger documentation is more honest than any tutorial,
   including this one.** This guide is built from the swagger, but
   the swagger ships with the appliance and updates with it.
6. **For recovery operations, the action is in the `Zic-Action`
   header.** It's easy to miss and the error message
   (`RecoveryInvalidZicAction`) is unmistakable when you do.
7. **Edits to existing VPGs are full PUTs, not partial PATCHes.**
   `UpdateVpgConfigurationModel` rejects any body missing
   `general`, `protectedResources`, `replication`, or `recovery`,
   and rejects any unknown extra field. Do a GET, mutate in memory,
   PUT the whole thing back. Step 9 is the template.

That's the whole guide. Good luck — once you've got step 1 working,
the rest is mostly just patience and reading the JSON.
