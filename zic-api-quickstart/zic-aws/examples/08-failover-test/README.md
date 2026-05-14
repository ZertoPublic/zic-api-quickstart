# 08 — Run a non-disruptive failover test

Every recovery action in ZIC — failover, test, commit, rollback — is
the **same endpoint**. The action verb is in a request header, not
in the URL. This keeps the recovery surface tight: one route, five
operations.

## The endpoint

```
PUT  https://<zic-host>/zic/api/v1/vpgs/{vpgId}/failover
     Authorization: Bearer <token>
     Content-Type:  application/json
     Zic-Action:    <one of: failover | failoverCommit | failoverRollback | failoverTest | failoverTestStop>

     {
       "recoveryOperation": {
         "checkpointId":                <int>,
         "shutdownProtectedVmsOnCommit": false,
         "reverseProtectVpgOnCommit":    false
       }
     }

→ 202 Accepted (no body)
```

## The Zic-Action values

From the swagger description on the endpoint:

| `Zic-Action` | What it does |
| ------------ | ------------ |
| `failover` | **Live failover.** Recovers production into the recovery region. Disruptive. |
| `failoverTest` | **Non-disruptive test.** Spins up test VMs in the recovery region without affecting production. ← *what this example does* |
| `failoverTestStop` | Tears down a running test. Used to clean up after `failoverTest`. |
| `failoverCommit` | After a live failover, finalize the recovery (point of no return). |
| `failoverRollback` | After a live failover, return to the original protected side. |

If you pass an invalid value, the API returns `RecoveryInvalidZicAction`.

## What the body fields do

- **`checkpointId`** — Which point-in-time to recover to. Get this
  from `GET /api/v1/vpgs/{vpgId}/checkpoints`. The script picks the
  latest checkpoint automatically.
- **`shutdownProtectedVmsOnCommit`** — For live failover only. If
  `true`, shuts down the source VMs after a successful commit.
  Ignored for tests.
- **`reverseProtectVpgOnCommit`** — For live failover only. If
  `true`, sets up reverse protection (source ← recovery) after
  commit, so you can fail back later. Ignored for tests.

## A complete test flow

```
1. GET   /api/v1/vpgs/{vpgId}/checkpoints       → pick a checkpoint
2. PUT   /api/v1/vpgs/{vpgId}/failover          → Zic-Action: failoverTest
3. Poll  /api/v1/tasks/{taskId} until Completed/Success
4. ... your team manually validates the test VMs ...
5. PUT   /api/v1/vpgs/{vpgId}/failover          → Zic-Action: failoverTestStop
6. Poll  the second task until Completed/Success
```

The included scripts do steps 1, 2, and 3. They print the exact
command for step 5 when the test is up and running so you can
trigger the teardown when you're ready.

## ⚠ Safety

This example **only** performs `failoverTest`. It is non-disruptive
— it spins test VMs up in the recovery region using the
`failoverTest` network config (from the VPG's recovery defaults),
leaving your production source untouched.

**Don't change `ZIC_ACTION` to `failover` to "see what happens" in a
running environment.** Live failover replaces production. Run that
in a lab, with eyes open and a runbook in hand.

## Run it

```bash
# Pass the vpgId (from example 02)
./failover-test.sh '<vpgId>'
python3 failover_test.py '<vpgId>'
./Failover-Test.ps1 '<vpgId>'
```

Output:

```
→ GET    /api/v1/vpgs/<vpgId>/checkpoints
  picked checkpoint 1715670763 (2026-05-14T09:12:43Z)

→ PUT    /api/v1/vpgs/<vpgId>/failover  [Zic-Action: failoverTest]
  202 Accepted — failover test queued

→ following task ...
[09:13:48]  status=Running       progress= 20.0  operationType=FailoverTest
[09:13:53]  status=Running       progress= 65.0  operationType=FailoverTest
[09:13:58]  status=Completed     progress=100.0  operationType=FailoverTest
✓ Failover test is now running.

When ready to tear down the test, run:
  curl -k -X PUT \
    -H "Authorization: Bearer $(./../01-get-token/get-token.sh)" \
    -H "Content-Type: application/json" \
    -H "Zic-Action: failoverTestStop" \
    -d '{"recoveryOperation":{"checkpointId":0,"shutdownProtectedVmsOnCommit":false,"reverseProtectVpgOnCommit":false}}' \
    https://<zic-host>/zic/api/v1/vpgs/<vpgId>/failover
```

## Adjacent endpoints

- `GET  /api/v1/vpgs/{vpgId}/checkpoints` — list recovery checkpoints
  for a VPG.
- `POST /api/v1/vpgs/{vpgId}/checkpoints` — insert a tagged
  checkpoint (e.g. before a known-good state for later recovery).
