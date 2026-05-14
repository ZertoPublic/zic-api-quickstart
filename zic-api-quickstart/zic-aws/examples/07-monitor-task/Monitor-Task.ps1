# ─────────────────────────────────────────────────────────────────────────
# Poll a ZIC task until it reaches a terminal state.
# Usage:  ./Monitor-Task.ps1 '<task-id>'
#
# Exit codes:
#   0 — taskCompletionStatus == Success
#   1 — taskCompletionStatus in {Failed, Cancelled, PartialSuccess}
#   2 — bad usage
# ─────────────────────────────────────────────────────────────────────────

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$TaskId,

    [int]$IntervalSeconds = $(if ($env:POLL_INTERVAL) { [int]$env:POLL_INTERVAL } else { 5 })
)

. "$PSScriptRoot/../01-get-token/Get-Token.ps1"

$Hostname  = $env:ZIC_HOST
$ApiBase   = if ($env:ZIC_API_BASE) { $env:ZIC_API_BASE } else { "https://$Hostname/zic/api/v1" }
$VerifyTls = $env:ZIC_VERIFY_TLS -eq "true"

if (-not $Hostname) { throw "ZIC_HOST is required" }

while ($true) {
    $token = Get-ZicToken
    $params = @{
        Uri     = "$ApiBase/tasks/$TaskId"
        Method  = "Get"
        Headers = @{
            "Authorization" = "Bearer $token"
            "Accept"        = "application/json"
        }
    }
    if (-not $VerifyTls) { $params["SkipCertificateCheck"] = $true }

    $task       = Invoke-RestMethod @params
    $status     = $task.status
    $progress   = $task.progress
    $op         = $task.operationType
    $completion = $task.taskResult.taskCompletionStatus
    $reason     = $task.taskResult.failureReason

    $ts = (Get-Date).ToString("HH:mm:ss")
    Write-Host ("[{0}]  status={1,-30} progress={2,5:N1}  operationType={3}" -f $ts, $status, $progress, $op)

    if ($status -eq "Completed") {
        if ($completion -eq "Success") {
            Write-Host "✓ Task completed with status: Success"
            exit 0
        }
        Write-Error "Task completed with status: $completion"
        if ($reason) {
            Write-Error "  failureReason: $reason"
        }
        exit 1
    }

    Start-Sleep -Seconds $IntervalSeconds
}
