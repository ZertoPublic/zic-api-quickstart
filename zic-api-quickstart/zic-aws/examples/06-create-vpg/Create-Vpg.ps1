# ─────────────────────────────────────────────────────────────────────────
# Create a VPG via the ZIC API (single POST + task lookup).
# Usage:
#   ./Create-Vpg.ps1                          # uses default-vpg-body.json
#   ./Create-Vpg.ps1 -BodyPath my-body.json
# ─────────────────────────────────────────────────────────────────────────

param(
    [string]$BodyPath = "$PSScriptRoot/default-vpg-body.json"
)

. "$PSScriptRoot/../01-get-token/Get-Token.ps1"

$Hostname  = $env:ZIC_HOST
$ApiBase   = if ($env:ZIC_API_BASE) { $env:ZIC_API_BASE } else { "https://$Hostname/zic/api/v1" }
$VerifyTls = $env:ZIC_VERIFY_TLS -eq "true"

if (-not $Hostname) { throw "ZIC_HOST is required" }
if (-not (Test-Path $BodyPath)) { throw "body file not found: $BodyPath" }

$raw = Get-Content $BodyPath -Raw
if ($raw -match "REPLACE_ME") {
    throw "$BodyPath still contains REPLACE_ME placeholders. Edit it first."
}

$token = Get-ZicToken
$headers = @{
    "Authorization" = "Bearer $token"
    "Accept"        = "application/json"
}

Write-Host "→ POST $ApiBase/vpgs"
$createParams = @{
    Uri             = "$ApiBase/vpgs"
    Method          = "Post"
    Headers         = $headers
    ContentType     = "application/json"
    Body            = $raw
    StatusCodeVariable = "statusCode"
}
if (-not $VerifyTls) { $createParams["SkipCertificateCheck"] = $true }
try {
    $null = Invoke-RestMethod @createParams
} catch {
    Write-Error ("ERROR creating VPG: $($_.Exception.Message)`n" +
                 "Response: $($_.ErrorDetails.Message)")
    exit 1
}

if ($statusCode -ne 202) {
    Write-Error "Expected 202 Accepted, got $statusCode"
    exit 1
}
Write-Host "  202 Accepted — VPG creation queued`n"

Write-Host "→ GET $ApiBase/tasks?top=1"
$taskParams = @{
    Uri     = "$ApiBase/tasks?top=1"
    Method  = "Get"
    Headers = $headers
}
if (-not $VerifyTls) { $taskParams["SkipCertificateCheck"] = $true }
$tasksResp = Invoke-RestMethod @taskParams

if (-not $tasksResp.tasks -or $tasksResp.tasks.Count -eq 0) {
    Write-Warning "no recent task found. The VPG may still be processing."
    return
}

$task   = $tasksResp.tasks[0]
$taskId = $task.taskId.id
$op     = $task.operationType
Write-Host "  most recent task: $taskId  (operationType=$op)`n"
Write-Host "Hand this task ID to example 07 to watch it complete:"
Write-Host "  cd ../07-monitor-task; ./Monitor-Task.ps1 '$taskId'"
