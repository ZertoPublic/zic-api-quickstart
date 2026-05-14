# ─────────────────────────────────────────────────────────────────────────
# List AWS regions the ZIC appliance is enabled for.
# ─────────────────────────────────────────────────────────────────────────

. "$PSScriptRoot/../01-get-token/Get-Token.ps1"

$Hostname  = $env:ZIC_HOST
$ApiBase   = if ($env:ZIC_API_BASE) { $env:ZIC_API_BASE } else { "https://$Hostname/zic/api/v1" }
$VerifyTls = $env:ZIC_VERIFY_TLS -eq "true"

if (-not $Hostname) { throw "ZIC_HOST is required" }

$token = Get-ZicToken
$params = @{
    Uri     = "$ApiBase/regions"
    Method  = "Get"
    Headers = @{
        "Authorization" = "Bearer $token"
        "Accept"        = "application/json"
    }
}
if (-not $VerifyTls) { $params["SkipCertificateCheck"] = $true }

$resp    = Invoke-RestMethod @params
$regions = $resp.regions

if (-not $regions -or $regions.Count -eq 0) {
    Write-Host "(no regions enabled on this appliance)"
    return
}

Write-Host "$($regions.Count) region(s) enabled:`n"

$regions | ForEach-Object {
    [PSCustomObject]@{
        id   = $_.id
        name = $_.name
    }
} | Format-Table -AutoSize
