# ─────────────────────────────────────────────────────────────────────────
# Kick off a non-disruptive failover test on a VPG.
# Usage:  ./Failover-Test.ps1 '<vpgId>'
#
# Hardcoded to Zic-Action: failoverTest — non-disruptive.
# DO NOT change $ZicAction to "failover" without understanding what it
# will do to your production workload.
# ─────────────────────────────────────────────────────────────────────────

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$VpgId
)

. "$PSScriptRoot/../01-get-token/Get-Token.ps1"

$Hostname  = $env:ZIC_HOST
$ApiBase   = if ($env:ZIC_API_BASE) { $env:ZIC_API_BASE } else { "https://$Hostname/zic/api/v1" }
$VerifyTls = $env:ZIC_VERIFY_TLS -eq "true"
$ZicAction = "failoverTest"

if (-not $Hostname) { throw "ZIC_HOST is required" }

$token = Get-ZicToken
$baseHeaders = @{
    "Authorization" = "Bearer $token"
    "Accept"        = "application/json"
}

# 1) List checkpoints.
Write-Host "→ GET    $ApiBase/vpgs/$VpgId/checkpoints"
$cpParams = @{
    Uri     = "$ApiBase/vpgs/$VpgId/checkpoints"
    Method  = "Get"
    Headers = $baseHeaders
}
if (-not $VerifyTls) { $cpParams["SkipCertificateCheck"] = $true }
$cpResp = Invoke-RestMethod @cpParams

# Try common envelope shapes
$checkpoints = if ($cpResp.checkpoints) { $cpResp.checkpoints }
               elseif ($cpResp -is [array]) { $cpResp }
               else { @() }

if ($checkpoints.Count -eq 0) {
    throw "no checkpoints available on this VPG"
}

$latest = $checkpoints | Sort-Object timeStamp | Select-Object -Last 1
$cpId = if ($latest.checkpointId.id) { $latest.checkpointId.id }
        elseif ($latest.checkpointId)    { $latest.checkpointId }
        else { $latest.CheckpointId }
Write-Host "  picked checkpoint $cpId  ($($latest.timeStamp))`n"

# 2) PUT failover with Zic-Action header.
$body = @{
    recoveryOperation = @{
        checkpointId                = $cpId
        shutdownProtectedVmsOnCommit = $false
        reverseProtectVpgOnCommit    = $false
    }
} | ConvertTo-Json -Depth 5

Write-Host "→ PUT    $ApiBase/vpgs/$VpgId/failover  [Zic-Action: $ZicAction]"
$putHeaders = $baseHeaders.Clone()
$putHeaders["Zic-Action"] = $ZicAction

$putParams = @{
    Uri                = "$ApiBase/vpgs/$VpgId/failover"
    Method             = "Put"
    Headers            = $putHeaders
    ContentType        = "application/json"
    Body               = $body
    StatusCodeVariable = "statusCode"
}
if (-not $VerifyTls) { $putParams["SkipCertificateCheck"] = $true }
try {
    $null = Invoke-RestMethod @putParams
} catch {
    Write-Error "ERROR triggering failover test: $($_.Exception.Message)`nResponse: $($_.ErrorDetails.Message)"
    exit 1
}

if ($statusCode -ne 202) {
    Write-Error "Expected 202 Accepted, got $statusCode"
    exit 1
}
Write-Host "  202 Accepted — failover test queued`n"

# 3) Find the task and follow it.
Write-Host "→ following task ..."
Start-Sleep -Seconds 2

$taskParams = @{
    Uri     = "$ApiBase/tasks?top=1"
    Method  = "Get"
    Headers = $baseHeaders
}
if (-not $VerifyTls) { $taskParams["SkipCertificateCheck"] = $true }
$tasksResp = Invoke-RestMethod @taskParams
$taskId = $tasksResp.tasks[0].taskId.id

& "$PSScriptRoot/../07-monitor-task/Monitor-Task.ps1" $taskId
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "✓ Failover test is now running."
Write-Host ""
Write-Host "When ready to tear down the test, run:"
Write-Host "  `$token = ./../01-get-token/Get-Token.ps1"
Write-Host "  Invoke-RestMethod -Method Put -SkipCertificateCheck \``"
Write-Host "    -Uri '$ApiBase/vpgs/$VpgId/failover' \``"
Write-Host "    -Headers @{'Authorization'='Bearer ' + \$token; 'Zic-Action'='failoverTestStop'} \``"
Write-Host "    -ContentType 'application/json' \``"
Write-Host "    -Body '{`"recoveryOperation`":{`"checkpointId`":0,`"shutdownProtectedVmsOnCommit`":false,`"reverseProtectVpgOnCommit`":false}}'"
