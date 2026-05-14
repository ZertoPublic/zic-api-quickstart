# 05 — List alerts

Active alerts on the appliance, with optional filtering.

## The endpoint

```
GET  https://<zic-host>/zic/api/v1/alerts
     Authorization: Bearer <token>

# Useful filters (all optional)
?isDismissed=false
?level=Warning
?vpgIdentifier=<vpgId>
?startDate=2026-05-01T00:00:00Z
?endDate=2026-05-14T23:59:59Z
```

Response (`AlertsInfoResponse`):

```json
{
  "alerts": [
    {
      "alertKey": {
        "failedEntityIdentifier": "abcdef12-...",
        "failureType":            "RPO"
      },
      "alertEntity":      "VPG",
      "alertLevel":       "Warning",
      "alertDescription": "VPG web-tier is not meeting RPO target of 00:05:00",
      "startTime":        "2026-05-14T09:12:43Z",
      "alertHelpId":      "ZIC0006",
      "vpgId":            "abcdef12-...",
      "isDismissed":      false,
      "reasons":          "..."
    }
  ]
}
```

## Enum values

| Field | Values |
| ----- | ------ |
| `alertEntity` | `ZIC`, `VPG` |
| `alertLevel` | `Warning` (the swagger only defines this one value — Errors may be modeled differently, e.g. as a separate `entity` of `ZIC`) |
| `alertKey.failureType` | `RPO`, `History`, `SLA`, `NeedsConfig`, `License`, `NoRegionConnectivity`, `LicenseIsAboutToReachVmLimit`, `LicenseVmLimitReached`, `MemberAccountDbEncryptionFailed` |

## Dismiss / undismiss an alert

ZIC uses `PUT` (not `POST`) with the `alertKey` block as the body —
not just an ID. The `failedEntityIdentifier` + `failureType` pair
together identify the alert:

```
PUT  https://<zic-host>/zic/api/v1/alerts/dismiss
Content-Type: application/json

{
  "failedEntityIdentifier": "abcdef12-...",
  "failureType":            "RPO"
}
```

To re-raise a dismissed alert: same body, but to `/alerts/undismiss`.

## Routing alerts downstream

The two fields you build automation around:

- **`alertHelpId`** (e.g. `ZIC0006`) — stable across versions. Map
  to PagerDuty service / Slack channel / email DL.
- **`alertKey.failureType`** — coarser-grained but useful for
  bucketing. RPO and SLA → ops; License → billing; NeedsConfig →
  whoever owns appliance config.

Never route on `alertDescription` text — it's reworded between
versions.

## Adjacent endpoints

- `PUT /api/v1/alerts` — get a single alert by `AlertKey` (the
  swagger documents this as a PUT for technical reasons; it's read-
  only despite the verb).
- `PUT /api/v1/alerts/dismiss` — see above.
- `PUT /api/v1/alerts/undismiss` — re-raise a dismissed alert.

## Run it

```bash
./list-alerts.sh
python3 list_alerts.py
./List-Alerts.ps1
```
