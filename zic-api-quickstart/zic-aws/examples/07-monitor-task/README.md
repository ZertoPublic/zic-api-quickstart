# 07 — Monitor a task to completion

Most write operations on the ZIC API are asynchronous: the appliance
accepts your request, returns 202, queues the work, and exposes a
task record you can poll.

## The endpoint

```
GET  https://<zic-host>/zic/api/v1/tasks/{taskId}
     Authorization: Bearer <token>
```

Response (`TaskInfoModel`):

```json
{
  "taskId":          { "id": "8f4a7c2b-..." },
  "startTime":       "2026-05-14T09:12:43Z",
  "endTime":         null,
  "status":          "Running",
  "progress":        45.0,
  "vpgId":           "abcdef12-...",
  "memberAccountId": "123456789012",
  "operationType":   "CreateVpg",
  "taskResult": {
    "taskCompletionStatus": null,
    "failureReason":        null,
    "specificTaskResult":   null
  }
}
```

## The two-level status model

The ZIC task model has **two** status fields, and you need both to
know what actually happened. This is a real footgun if you only
check the first one:

**`status`** — the state machine. Values from `ZTaskStatusModel`:

| `status` | Done? | What it means |
| -------- | ----- | ------------- |
| `NotStarted` | no | Task queued, not yet executing. |
| `Running` | no | Task is executing. |
| `RunningCancellationRequested` | no | Task is executing but a cancel was requested. |
| `Completed` | **yes** | Task finished. **Does NOT mean success.** |

**`taskResult.taskCompletionStatus`** — the outcome. Only populated
when `status == "Completed"`. Values from `TaskCompletionStatusModel`:

| `taskCompletionStatus` | What it means |
| ---------------------- | ------------- |
| `Success` | The work succeeded. |
| `Failed` | The work failed. Read `taskResult.failureReason` for why. |
| `Cancelled` | The cancellation took effect. |
| `PartialSuccess` | Some sub-operations succeeded and some didn't. Read `failureReason`. |

So a polling loop is: poll until `status == "Completed"`, then read
`taskCompletionStatus` to decide whether to celebrate or roll back.

## operationType values

Useful when listing tasks to figure out what they correspond to:

`CreateVpg`, `UpdateVpg`, `DeleteVpg`, `FailoverLive`, `FailoverTest`,
`FailoverTestStop`, `FailoverLiveCommit`, `FailoverLiveRollback`,
`LogCollection`, `InsertVpgCheckpoint`, `ReverseProtectVpg`,
`CreateMemberAccount`, `UpdateMemberAccount`, `DeleteMemberAccount`.

## Finding a task ID

If you have the ID from a previous step (example 06 prints it), pass
it directly. If you don't:

```
GET /api/v1/tasks?top=1
GET /api/v1/tasks?topPerProperty=VpgId&top=1
```

The first returns the most recent task globally. The second returns
the most recent task per VPG (the only valid `topPerProperty` value
is `VpgId`, per the swagger).

> **Note:** `top` must be `> 0` — passing `0` returns
> `TasksTopPropertyMustBeGreaterThanZero`.

## Run it

```bash
./monitor-task.sh '<task-id>'
python3 monitor_task.py '<task-id>'
./Monitor-Task.ps1 '<task-id>'
```

Output looks like:

```
[09:12:48]  status=Running          progress= 15.0  operationType=CreateVpg
[09:12:53]  status=Running          progress= 35.0  operationType=CreateVpg
[09:12:58]  status=Running          progress= 80.0  operationType=CreateVpg
[09:13:03]  status=Completed        progress=100.0  operationType=CreateVpg
✓ Task completed with status: Success
```

Exit code `0` only on `taskCompletionStatus == Success` — `Failed`,
`Cancelled`, and `PartialSuccess` all exit non-zero so you can use
this script in CI / make-style pipelines.

## Adjacent endpoints

- `GET /api/v1/tasks` — list tasks (use `top` to limit).
- `GET /api/v1/tasks/{taskId}` — single task detail (this script).
