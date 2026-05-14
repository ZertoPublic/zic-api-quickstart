# 03 — List regions

ZIC's "where can I protect from / recover to?" is answered by AWS
regions, not by a paired-peer-site concept like ZVM uses.

## The endpoint

```
GET  https://<zic-host>/zic/api/v1/regions
     Authorization: Bearer <token>
```

The swagger description: *"Gets list of regions from the platform.
The region list contains only regions which are enabled for the
requested account."*

Response (`RegionsResponse`):

```json
{
  "regions": [
    { "id": "us-east-1", "name": "US East (N. Virginia)" },
    { "id": "us-west-2", "name": "US West (Oregon)" },
    { "id": "eu-west-1", "name": "Europe (Ireland)" }
  ]
}
```

The `id` is a stable AWS region code. The `name` is the human-readable
label.

## Why this matters

You'll read this list right before creating a VPG. The VPG body
needs region IDs for two slots:

- `vpg.general.protectedRegion.id` — source AWS region
- `vpg.general.recoveryRegion.id` — destination AWS region

Both have to be in the list returned by this endpoint. Pasting in an
arbitrary AWS region code that isn't enabled on the appliance will
fail with `InvalidRegionIdentifier`.

## Adjacent endpoints

Once you've picked a region, the resource endpoints scoped to it let
you discover what's available for VPG creation:

- `GET /api/v1/regions/{regionId}/resources/vms`
  — list EC2 VMs (see example 04)
- `GET /api/v1/regions/{regionId}/resources/vms/{vmId}/nics`
  — list NICs for one VM
- `GET /api/v1/regions/{regionId}/resources/vnets`
  — list VPCs
- `GET /api/v1/regions/{regionId}/resources/vnets/{vnetId}/subnets`
  — list subnets in a VPC
- `GET /api/v1/regions/{regionId}/resources/vnets/{vnetId}/sgroups`
  — list security groups in a VPC
- `GET /api/v1/regions/{regionId}/resources/subnets/{subnetId}`
  — detail for one subnet
- `GET /api/v1/regions/{regionId}/resources/keypairs`
  — list EC2 key pairs

All of these return the AWS identifiers (`vm-...`, `subnet-...`,
`vpc-...`, `sg-...`, key pair names) you'll plug into the VPG
recovery config in step 6.

## Run it

```bash
./list-regions.sh
python3 list_regions.py
./List-Regions.ps1
```
