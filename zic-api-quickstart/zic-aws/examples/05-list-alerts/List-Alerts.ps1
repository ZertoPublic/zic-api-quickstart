# ─────────────────────────────────────────────────────────────────────────
# List active (non-dismissed) alerts on the ZIC appliance.
# ─────────────────────────────────────────────────────────────────────────

. "$PSScriptRoot/../01-get-token/Get-Token.ps1"

$Hostname  = $env:ZIC_HOST
$ApiBase   = if ($env:ZIC_API_BASE) { $env:ZIC_API_BASE } else { "https://$Hostname/zic/api/v1" }
$VerifyTls = $env:ZIC_VERIFY_TLS -eq "true"

if (-not $Hostname) { throw "ZIC_HOST is required" }

$token = Get-ZicToken
$params = @{
    Uri     = "$ApiBase/alerts?isDismissed=false"
    Method  = "Get"
    Headers = @{
        "Authorization" = "Bearer $token"
        "Accept"        = "application/json"
    }
}
if (-not $VerifyTls) { $params["SkipCertificateCheck"] = $true }

$resp   = Invoke-RestMethod @params
$alerts = $resp.alerts

if (-not $alerts -or $alerts.Count -eq 0) {
    Write-Host "No active alerts."
    return
}

Write-Host "$($alerts.Count) active alert(s):`n"
foreach ($a in $alerts) {
    $ftype = $a.alertKey.failureType
    Write-Host "[$($a.alertLevel)]  $($a.alertHelpId)  ($($a.alertEntity)/$ftype)"
    Write-Host "        startTime: $($a.startTime)"
    Write-Host "        vpgId:     $($a.vpgId ?? '-')"
    Write-Host "        $($a.alertDescription)`n"
}
