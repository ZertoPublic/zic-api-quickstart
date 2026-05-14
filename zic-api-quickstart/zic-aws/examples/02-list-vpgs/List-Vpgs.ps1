# ─────────────────────────────────────────────────────────────────────────
# List every VPG on the ZIC appliance.
# ─────────────────────────────────────────────────────────────────────────

. "$PSScriptRoot/../01-get-token/Get-Token.ps1"

$Hostname  = $env:ZIC_HOST
$ApiBase   = if ($env:ZIC_API_BASE) { $env:ZIC_API_BASE } else { "https://$Hostname/zic/api/v1" }
$VerifyTls = $env:ZIC_VERIFY_TLS -eq "true"

if (-not $Hostname) { throw "ZIC_HOST is required" }

$token = Get-ZicToken

$params = @{
    Uri     = "$ApiBase/vpgs"
    Method  = "Get"
    Headers = @{
        "Authorization" = "Bearer $token"
        "Accept"        = "application/json"
    }
}
if (-not $VerifyTls) { $params["SkipCertificateCheck"] = $true }

$resp = Invoke-RestMethod @params

$vpgs     = $resp.vpgs
$degraded = $resp.vpgsWithoutData

if ((-not $vpgs -or $vpgs.Count -eq 0) -and (-not $degraded -or $degraded.Count -eq 0)) {
    Write-Host "(no VPGs on this appliance)"
    return
}

$vpgs | ForEach-Object {
    [PSCustomObject]@{
        Name             = $_.vpgInfo.general.name
        vpgState         = $_.vpgState
        protectionStatus = $_.replicationInfo.replicationStatistics.protectionStatus
        actualRpo        = $_.replicationInfo.replicationStatistics.actualRpo
        VMs              = ($_.vpgInfo.protectedResources.vms | Measure-Object).Count
    }
} | Format-Table -AutoSize

if ($degraded -and $degraded.Count -gt 0) {
    Write-Host ""
    Write-Host "⚠ $($degraded.Count) VPG(s) returned without full data (vpgsWithoutData)."
}
