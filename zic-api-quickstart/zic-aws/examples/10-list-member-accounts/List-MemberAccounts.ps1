# ─────────────────────────────────────────────────────────────────────────
# List member accounts on a ZIC v2 appliance.
# Usage:
#   ./List-MemberAccounts.ps1
#   ./List-MemberAccounts.ps1 -Stats
# ─────────────────────────────────────────────────────────────────────────

param(
    [switch]$Stats
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

Write-Host "→ GET    $V2Base/zicconfiguration/memberaccounts"
$listParams = @{
    Uri     = "$V2Base/zicconfiguration/memberaccounts"
    Method  = "Get"
    Headers = $headers
}
if (-not $VerifyTls) { $listParams["SkipCertificateCheck"] = $true }
$resp = Invoke-RestMethod @listParams

if (-not $resp.accounts -or $resp.accounts.Count -eq 0) {
    Write-Host "(no member accounts configured)"
    return
}

Write-Host "  $($resp.accounts.Count) member account(s):`n"
foreach ($a in $resp.accounts) {
    $aid    = $a.accountId.id
    $desc   = if ($a.description) { $a.description } else { "-" }
    $status = $a.status
    if ($a.statusDescription) { $status = "$status  — $($a.statusDescription)" }
    $ext    = if ($a.externalId) { $a.externalId } else { "-" }
    $cmkn   = if ($a.cmksPerRegion) { @($a.cmksPerRegion).Count } else { 0 }

    Write-Host "  accountId: $aid"
    Write-Host "    description:    $desc"
    Write-Host "    status:         $status"
    Write-Host "    externalId:     $ext"
    Write-Host "    cmksPerRegion:  $cmkn configured"
    Write-Host ""
}

if ($Stats) {
    Write-Host "→ GET    $V2Base/zicconfiguration/memberaccounts/statistics"
    $statParams = @{
        Uri     = "$V2Base/zicconfiguration/memberaccounts/statistics"
        Method  = "Get"
        Headers = $headers
    }
    if (-not $VerifyTls) { $statParams["SkipCertificateCheck"] = $true }
    $statsResp = Invoke-RestMethod @statParams

    Write-Host ""
    $statsResp.accounts | ForEach-Object {
        [PSCustomObject]@{
            accountId    = $_.accountId.id
            protectedVms = $_.protectedVms
            totalVpgs    = $_.totalVpgs
        }
    } | Format-Table -AutoSize
}
