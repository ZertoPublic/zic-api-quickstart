# 09 — Manage tags on an existing VPG

Update the `recovery.default.tags` array on a VPG that already exists.
Tags get applied to recovery VMs at failover time (see example 06's
README for the full story).

## The read-modify-write pattern

This is the first example in the repo where you **can't just send a
partial body**. ZIC's update endpoint takes a full `EditVpgRequest`,
not a JSON Patch / merge patch. So the flow is:

```
1. GET   /api/v1/vpgs                      → find the VPG, get vpgId + current config
2. (in memory) swap the tags in the config
3. PUT   /api/v1/vpgs/{vpgId}              → send the whole modified config back
4. Poll  /api/v1/tasks/{taskId}            → wait for UpdateVpg to complete
```

This isn't a quirk of this example — it's the swagger contract.
`UpdateVpgConfigurationModel` is declared with `additionalProperties:
false` and `required: [general, protectedResources, recovery,
replication]`. Sending three of four blocks rejects with
`InvalidEditVpgRequest`.

## The body shape

`EditVpgRequest` (verified from the swagger):

```json
{
  "vpg": {
    "general":            { "name": "...", "description": "..." },
    "protectedResources": { "vms": [ { "id": "i-0abc..." } ] },
    "replication":        { "sla": { "rpo": "...", "rpoAlert": "...", "history": "..." } },
    "recovery": {
      "default": {
        "network":        { ... },
        "keyPair":        { ... },
        "role":           { ... },
        "tags":           [ ... ← edit these ... ],
        "launchTemplate": { ... }
      },
      "vms": [ ... ]
    }
  }
}
```

> **What you can and can't change.** The PUT's `general` block is
> typed as `UpdateVpgGeneralConfigurationModel`, which only has
> `name` and `description` — **not** `protectedRegion`,
> `protectedAccount`, `recoveryRegion`, or `recoveryAccount`. Those
> are immutable on an existing VPG; you can't move a VPG between
> regions or accounts. To change them, delete and recreate.

## The GET → PUT transform

The GET response (`VpgInfoModel.vpgInfo`) and the PUT body share
three of four sub-trees verbatim:

| Block | GET-side schema | PUT-side schema | Transform |
| ----- | --------------- | --------------- | --------- |
| `protectedResources` | `VpgProtectedResourcesInfoModel` | `VpgProtectedResourcesConfigurationModel` | Same shape — copy as-is. |
| `replication` | `VpgReplicationInfoModel` | `VpgReplicationConfigurationModel` | Same shape — copy as-is. |
| `recovery` | `VpgRecoveryInfoModel` | `VpgRecoveryConfigurationModel` | Same shape — copy as-is, then mutate `default.tags`. |
| `general` | `VpgGeneralInfoModel` | `UpdateVpgGeneralConfigurationModel` | **Strip** the region/account fields — keep only `name` and `description`. |

The script does this for you. If you write your own tooling, the
"strip immutable fields from general" step is the only non-trivial
part.

## What this script does

```
$ ./manage-tags.sh <vpg-name>                    # show current tags
$ ./manage-tags.sh <vpg-name> add  Owner alice   # add or update one tag
$ ./manage-tags.sh <vpg-name> rm   Owner         # remove one tag by key
$ ./manage-tags.sh <vpg-name> set  '[{...},...]' # replace the whole tag set
$ ./manage-tags.sh <vpg-name> clear              # remove all tags
```

Behind the scenes, every mutating action runs the full GET → modify →
PUT → poll cycle. The only difference between `add`, `rm`, `set`, and
`clear` is what they do to the in-memory tag array.

## Tag key uniqueness

The swagger doesn't explicitly forbid duplicate `tagKey` values in
the array, but AWS does — EC2 enforces uniqueness on tag keys per
resource. So `add` operates as an **upsert**: if a tag with that key
already exists, its value is replaced; otherwise the tag is
appended. This matches the behavior you'd expect from the AWS
console and avoids "two `Environment` tags, only one applied"
surprises at failover time.

## Error codes you might hit

| Error code | Likely cause |
| ---------- | ------------ |
| `InvalidEditVpgRequest` | Body shape problem — typically a missing required sub-block (`general`, `protectedResources`, `replication`, `recovery`) or a stray extra field. |
| `VpgNotFound` | The `vpgId` doesn't exist. Re-run example 02. |
| `InvalidVpgState` | VPG is in a state where edits aren't allowed (e.g. `FailoverTest`, `Recovered`). Wait for it to return to `Protecting`. |
| `VpgManagementTaskIsAlreadyRunning` | Another create/update/delete is in flight on this VPG. Wait, retry. |
| `RequestValidationError` | A constraint is violated — most often an empty `tagKey` (the schema marks it `minLength: 1`). |

## Run it

```bash
# Show current tags
./manage-tags.sh my-vpg-name
python3 manage_tags.py my-vpg-name
./Manage-Tags.ps1 my-vpg-name

# Add or update a tag (upsert by key)
./manage-tags.sh my-vpg-name add Owner alice
./manage-tags.sh my-vpg-name add Environment DR-failover

# Remove a tag by key
./manage-tags.sh my-vpg-name rm Owner

# Replace all tags at once (pass JSON)
./manage-tags.sh my-vpg-name set '[{"tagKey":"Env","tagValue":"DR"}]'

# Clear all tags
./manage-tags.sh my-vpg-name clear
```

After any mutating action the script polls the resulting
`UpdateVpg` task and prints the final tag set.

## Adjacent endpoints

- `GET    /api/v1/vpgs` — find the VPG and its current config
  (this script uses it).
- `PUT    /api/v1/vpgs/{vpgId}` — the update endpoint itself
  (this script uses it).
- `DELETE /api/v1/vpgs/{vpgId}` — delete a VPG (out of scope for
  this example, but uses the same task-polling pattern).

## Why this pattern matters beyond tags

Once you have the GET → modify → PUT → poll cycle working for tags,
it works identically for anything else on a VPG: RPO, security
groups, recovery subnet, key pair, launch template, per-VM overrides.
The only thing that changes is which field you mutate between the
GET and the PUT. Treat this script as the template for any "edit
VPG" automation.
