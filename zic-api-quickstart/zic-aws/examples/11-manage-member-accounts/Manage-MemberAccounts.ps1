# ─────────────────────────────────────────────────────────────────────────
# Manage member accounts on a ZIC v2 appliance.
# Usage:
#   ./Manage-MemberAccounts.ps1 -Action add  -AccountId <id> -ExternalId <id> [-Description <text>]
#   ./Manage-MemberAccounts.ps1 -Action edit -AccountId <id> -ExternalId <id> [-Description <text>]
#   ./Manage-MemberAccounts.ps1 -Action rm   -AccountId <id>
# ─────────────────────────────────────────────────────────────────────────

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("add", "edit", "rm")]
    [string]$Action,

    [Parameter(Mandatory=$true)]
    [string]$AccountId,

    [string]$ExternalId,
    [string]$Description
)

. "$PSScriptRoot/../01-get-token/Get-Token.ps1"

$Hostname  = $env:ZIC_HOST
$V2Base    = "https://$Hostname/zic/api/v2"
$VerifyTls = $env:ZIC_VERIFY_TLS -eq "true"

if (-not $Hostname) { throw "ZIC_HOST is required" }

$token = Get-ZicToken
$headers = @{
    "Authorization" = "Bearer $token"
    "Accept"        = "application/json"
}

$putHeaders = @{
    "Authorization" = "Bearer $token"
    "Accept"        = "application/json"
}

switch ($Action) {
    "add" {
        if (-not $ExternalId) { throw "'add' requires -ExternalId" }
        $body = @{
            accountId  = @{ id = $AccountId }
            externalId = $ExternalId
        }
        if ($Description) { $body.description = $Description }
        Write-Host "→ POST   $V2Base/zicconfiguration/memberaccounts"
        $params = @{
            Uri                = "$V2Base/zicconfiguration/memberaccounts"
            Method             = "Post"
            Headers            = $putHeaders
            ContentType        = "application/json"
            Body               = ($body | ConvertTo-Json -Depth 5)
            StatusCodeVariable = "statusCode"
        }
    }
    "edit" {
        if (-not $ExternalId) { throw "'edit' requires -ExternalId" }
        $body = @{ externalId = $ExternalId }
        if ($Description) { $body.description = $Description }
        Write-Host "→ PUT    $V2Base/zicconfiguration/memberaccounts/$AccountId"
        $params = @{
            Uri                = "$V2Base/zicconfiguration/memberaccounts/$AccountId"
            Method             = "Put"
            Headers            = $putHeaders
            ContentType        = "application/json"
            Body               = ($body | ConvertTo-Json -Depth 5)
            StatusCodeVariable = "statusCode"
        }
    }
    "rm" {
        Write-Host "→ DELETE $V2Base/zicconfiguration/memberaccounts/$AccountId"
        $params = @{
            Uri                = "$V2Base/zicconfiguration/memberaccounts/$AccountId"
            Method             = "Delete"
            Headers            = $headers
            StatusCodeVariable = "statusCode"
        }
    }
}

if (-not $VerifyTls) { $params["SkipCertificateCheck"] = $true }

try {
    $null = Invoke-RestMethod @params
} catch {
    Write-Error "ERROR: $($_.Exception.Message)`nResponse: $($_.ErrorDetails.Message)"
    exit 1
}

if ($statusCode -ne 202) {
    Write-Error "Expected 202 Accepted, got $statusCode"
    exit 1
}
Write-Host "  $statusCode — queued`n"

# Find the resulting task.
Write-Host "→ following task ..."
Start-Sleep -Seconds 2

$taskParams = @{
    Uri     = "$V2Base/tasks?top=1"
    Method  = "Get"
    Headers = $headers
}
if (-not $VerifyTls) { $taskParams["SkipCertificateCheck"] = $true }
$tasksResp = Invoke-RestMethod @taskParams
$taskId = $tasksResp.tasks[0].taskId.id

# Force the monitor onto v2 by overriding the env var for its duration.
$prevBase = $env:ZIC_API_BASE
$env:ZIC_API_BASE = $V2Base
try {
    & "$PSScriptRoot/../07-monitor-task/Monitor-Task.ps1" $taskId
    $rc = $LASTEXITCODE
} finally {
    $env:ZIC_API_BASE = $prevBase
}
exit $rc
