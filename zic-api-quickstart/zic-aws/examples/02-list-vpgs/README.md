# 02 — List VPGs

Read every Virtual Protection Group on the appliance.

## The endpoint

```
GET  https://<zic-host>/zic/api/v1/vpgs
     Authorization: Bearer <token>
```

Response (`VpgsInfoResponse`):

```json
{
  "vpgs": [
    {
      "vpgId":      "abcdef12-3456-7890-abcd-ef1234567890",
      "vpgState":   "Protecting",
      "vpgInfo": {
        "general": {
          "name":            "web-tier-prod",
          "description":     "Production web tier",
          "protectedRegion": { "id": "us-east-1", "name": "US East (N. Virginia)" },
          "recoveryRegion":  { "id": "us-west-2", "name": "US West (Oregon)" },
          "protectedAccount": { "accountId": "123456789012", ... },
          "recoveryAccount":  { "accountId": "123456789012", ... }
        },
        "protectedResources": { "vms": [ { "id": "i-0abc..." }, { "id": "i-0def..." } ] },
        "replication":  { "sla": { "rpo": "00:05:00", "rpoAlert": "00:10:00", "history": "1.00:00:00" } },
        "recovery":     { "default": { ... }, "vms": [ ... ] }
      },
      "replicationInfo": {
        "replicationStatistics": {
          "actualRpo":        "00:00:12",
          "actualHistory":    "0.23:45:00",
          "protectionStatus": "MeetingSLA",
          "replicationData":  { "latestCheckpoint": { ... }, "earliestCheckpoint": { ... }, "progress": 100, "isRecovered": false }
        },
        "replicationIssues": []
      },
      "recoveryInfo": { "failoverTestResult": { "lastSucceeded": "2026-04-30T14:22:00Z" } }
    }
  ],
  "vpgsWithoutData": []
}
```

## Enum values

| Field | Possible values |
| ----- | --------------- |
| `vpgState` | `Protecting`, `FailoverBeforeCommit`, `Recovered`, `FailoverTest`, `NeedsConfiguration` |
| `replicationInfo.replicationStatistics.protectionStatus` | `Na`, `Initializing`, `MeetingSLA`, `NotMeetingSLA`, `RpoNotMeetingSLA`, `HistoryNotMeetingSLA`, `Recovered` |

A healthy VPG: `vpgState: Protecting` + `protectionStatus: MeetingSLA`.

## On the duration fields

`actualRpo`, `actualHistory`, and the configured `rpo`/`rpoAlert`/
`history` are all .NET TimeSpan strings:

| String | Means |
| ------ | ----- |
| `"00:00:12"` | 12 seconds |
| `"00:05:00"` | 5 minutes |
| `"01:00:00"` | 1 hour |
| `"1.00:00:00"` | 1 day |
| `"7.00:00:00"` | 7 days |

If you need numeric seconds for downstream processing, parse the
string yourself — for `d.hh:mm:ss` the format is unambiguous.

## On `vpgsWithoutData`

When the appliance has a VPG record but can't currently load its
full configuration (e.g. a transient platform error talking to AWS),
the VPG's ID lands in `vpgsWithoutData` instead of `vpgs`. Treat it
as "exists but degraded" — the VPG didn't disappear, it just isn't
returning rich data right now.

## Adjacent endpoints

- `PUT /api/v1/vpgs/{vpgId}` — replace VPG configuration with an
  `EditVpgRequest`.
- `DELETE /api/v1/vpgs/{vpgId}` — delete (returns 202; check the
  task).
- `GET /api/v1/vpgs/{vpgId}/checkpoints` — list recovery checkpoints
  for one VPG.

## Run it

```bash
./list-vpgs.sh
python3 list_vpgs.py
./List-Vpgs.ps1
```

All three print a compact table: name, state, protection status,
actual RPO, instance count.
