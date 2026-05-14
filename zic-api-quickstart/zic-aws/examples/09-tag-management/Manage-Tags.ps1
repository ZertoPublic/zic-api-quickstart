# ─────────────────────────────────────────────────────────────────────────
# Manage recovery.default.tags on an existing VPG.
# Read-modify-write: GET full config → mutate tags → PUT it back → poll task.
#
# Usage:
#   ./Manage-Tags.ps1 -VpgName <name>
#   ./Manage-Tags.ps1 -VpgName <name> -Action add   -Key <k> -Value <v>
#   ./Manage-Tags.ps1 -VpgName <name> -Action rm    -Key <k>
#   ./Manage-Tags.ps1 -VpgName <name> -Action set   -TagsJson '<json>'
#   ./Manage-Tags.ps1 -VpgName <name> -Action clear
# ─────────────────────────────────────────────────────────────────────────

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$VpgName,

    [Parameter(Position=1)]
    [ValidateSet("show", "add", "rm", "set", "clear")]
    [string]$Action = "show",

    [string]$Key,
    [string]$Value,
    [string]$TagsJson
)

. "$PSScriptRoot/../01-get-token/Get-Token.ps1"

$Hostname  = $env:ZIC_HOST
$ApiBase   = if ($env:ZIC_API_BASE) { $env:ZIC_API_BASE } else { "https://$Hostname/zic/api/v1" }
$VerifyTls = $env:ZIC_VERIFY_TLS -eq "true"

if (-not $Hostname) { throw "ZIC_HOST is required" }

function Print-Tags($label, $tags) {
    Write-Host "${label}:"
    if (-not $tags -or @($tags).Count -eq 0) {
        Write-Host "  (none)"
        return
    }
    foreach ($t in $tags) {
        Write-Host "  $($t.tagKey) = $($t.tagValue)"
    }
}

$token = Get-ZicToken
$headers = @{
    "Authorization" = "Bearer $token"
    "Accept"        = "application/json"
}

# 1) GET all VPGs, find by name.
Write-Host "→ GET    $ApiBase/vpgs"
$listParams = @{
    Uri     = "$ApiBase/vpgs"
    Method  = "Get"
    Headers = $headers
}
if (-not $VerifyTls) { $listParams["SkipCertificateCheck"] = $true }
$resp = Invoke-RestMethod @listParams

$vpg = $resp.vpgs | Where-Object { $_.vpgInfo.general.name -eq $VpgName } | Select-Object -First 1
if (-not $vpg) {
    $available = ($resp.vpgs | ForEach-Object { $_.vpgInfo.general.name }) -join ", "
    throw "no VPG found with name '$VpgName'. Available: $available"
}

$vpgId = $vpg.vpgId
Write-Host "  resolved vpgId: $vpgId`n"

$currentTags = @()
if ($vpg.vpgInfo.recovery.default.tags) {
    $currentTags = @($vpg.vpgInfo.recovery.default.tags)
}
Print-Tags "Current tags" $currentTags

if ($Action -eq "show") {
    return
}

# 2) Compute the new tag set.
$newTags = switch ($Action) {
    "add" {
        if (-not $Key)   { throw "'add' requires -Key" }
        if (-not $Value) { $Value = "" }
        if ([string]::IsNullOrEmpty($Key)) {
            throw "tag key must be non-empty (swagger requires minLength: 1)"
        }
        # Upsert by key.
        $kept = @($currentTags | Where-Object { $_.tagKey -ne $Key })
        ,($kept + ,@{ tagKey = $Key; tagValue = $Value })
    }
    "rm" {
        if (-not $Key) { throw "'rm' requires -Key" }
        ,@($currentTags | Where-Object { $_.tagKey -ne $Key })
    }
    "set" {
        if (-not $TagsJson) { throw "'set' requires -TagsJson" }
        $parsed = $TagsJson | ConvertFrom-Json
        if ($parsed -isnot [array] -and -not ($parsed -is [System.Collections.IList])) {
            throw "'set' argument must be a JSON array"
        }
        ,@($parsed)
    }
    "clear" {
        ,@()
    }
}
$newTags = @($newTags)   # flatten any nested unrolling

Write-Host ""
Print-Tags "New tags (about to be applied)" $newTags

# 3) Build the EditVpgRequest body.
# Three blocks copied verbatim; general stripped of immutable region/account.
$body = @{
    vpg = @{
        general = @{
            name        = $vpg.vpgInfo.general.name
            description = $vpg.vpgInfo.general.description
        }
        protectedResources = $vpg.vpgInfo.protectedResources
        replication        = $vpg.vpgInfo.replication
        recovery           = $vpg.vpgInfo.recovery
    }
}
$body.vpg.recovery.default.tags = $newTags

$bodyJson = $body | ConvertTo-Json -Depth 20

# 4) PUT it back.
Write-Host "`n→ PUT    $ApiBase/vpgs/$vpgId"
$putParams = @{
    Uri                = "$ApiBase/vpgs/$vpgId"
    Method             = "Put"
    Headers            = $headers
    ContentType        = "application/json"
    Body               = $bodyJson
    StatusCodeVariable = "statusCode"
}
if (-not $VerifyTls) { $putParams["SkipCertificateCheck"] = $true }
try {
    $null = Invoke-RestMethod @putParams
} catch {
    Write-Error "ERROR updating VPG: $($_.Exception.Message)`nResponse: $($_.ErrorDetails.Message)"
    exit 1
}

if ($statusCode -ne 202) {
    Write-Error "Expected 202 Accepted, got $statusCode"
    exit 1
}
Write-Host "  202 Accepted — update queued"

# 5) Find the task and follow it.
Write-Host "`n→ following task ..."
Start-Sleep -Seconds 2

$taskParams = @{
    Uri     = "$ApiBase/tasks?top=1"
    Method  = "Get"
    Headers = $headers
}
if (-not $VerifyTls) { $taskParams["SkipCertificateCheck"] = $true }
$tasksResp = Invoke-RestMethod @taskParams
$taskId = $tasksResp.tasks[0].taskId.id

& "$PSScriptRoot/../07-monitor-task/Monitor-Task.ps1" $taskId
exit $LASTEXITCODE
