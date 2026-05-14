# 04 — List VMs in a region

For each AWS region the appliance is enabled for, this endpoint
returns the EC2 inventory along with each instance's protection
state. It's the closest thing ZIC has to a "what's protected" view.

## The endpoint

```
GET  https://<zic-host>/zic/api/v1/regions/{regionId}/resources/vms
     Authorization: Bearer <token>

# Optional tag filter (both required if either is used)
?tagName=Env&tagValue=prod
```

Response (`VmsResponse`):

```json
{
  "vms": [
    {
      "vmPropertiesModel": {
        "id":           "i-0abc123def456789",
        "name":         "web-01",
        "instanceType": "t3.medium",
        "vpcId":        "vpc-0abc...",
        "subnetId":     "subnet-0abc...",
        "...":          "..."
      },
      "additionalPropertiesModel": {
        "isProtected":     true,
        "protectedInVpgs": [ { "id": "abcdef12-..." } ]
      }
    }
  ]
}
```

> **Schema note.** The swagger defines `VmModel.vmPropertiesModel` as
> a polymorphic / loosely-typed object (`nullable: true` with no
> fixed properties listed at the model level). The exact field names
> inside `vmPropertiesModel` may vary by ZIC version — `id` and
> `name` are reliable, the rest you should inspect on first use.

## Three useful patterns

**1. Discovery for new VPGs.** Walk the list, grab the `id` of an
EC2 instance you want to protect, plug it into the VPG body in
step 6.

```
{ "vmPropertiesModel": { "id": "i-0abc..." }, "additionalPropertiesModel": { "isProtected": false } }
                          ^^^^^^^^^^^^^^^^^^
                          take this id
```

**2. Audit unprotected workloads.** Filter for
`additionalPropertiesModel.isProtected == false` to find everything
in the region that isn't covered.

**3. Tag-based automation.** Use `tagName` + `tagValue` query params
to scope to "every VM with tag `Protect=true`," then cross-check
which ones are already in VPGs. This is the foundation for
"automatically create a VPG for any new instance tagged for
protection."

## Adjacent resource endpoints

These all live under `/regions/{regionId}/resources/...`:

- `vms/{vmId}/nics` — NICs for one VM. Use when you need
  `NicIdentifierModel.id` for per-VM recovery overrides.
- `vnets` — VPCs in the region. Use for `virtualNetwork.id` in the
  recovery network config.
- `vnets/{vnetId}/subnets` — Subnets in a VPC. Use for `subnet.id`.
- `vnets/{vnetId}/sgroups` — Security groups in a VPC. Use for
  `securityGroups[].id`.
- `subnets/{subnetId}` — Detail for one subnet.
- `keypairs` — EC2 key pair names. Use for `keyPair.keyName`.

All of them follow the same pattern: GET with bearer token, JSON
response with the AWS identifiers ZIC expects.

## Run it

```bash
# Run example 03 first to find a region ID.
./list-vms-in-region.sh us-east-1
python3 list_vms_in_region.py us-east-1
./List-VmsInRegion.ps1 us-east-1
```
