# ─────────────────────────────────────────────────────────────────────────
# List EC2 VMs in a ZIC-enabled region, with protection state.
# Usage:  ./List-VmsInRegion.ps1 -Region us-east-1
#         ./List-VmsInRegion.ps1 -Region us-east-1 -TagName Env -TagValue prod
# ─────────────────────────────────────────────────────────────────────────

param(
    [Parameter(Mandatory=$true)][string]$Region,
    [string]$TagName,
    [string]$TagValue
)

. "$PSScriptRoot/../01-get-token/Get-Token.ps1"

$Hostname  = $env:ZIC_HOST
$ApiBase   = if ($env:ZIC_API_BASE) { $env:ZIC_API_BASE } else { "https://$Hostname/zic/api/v1" }
$VerifyTls = $env:ZIC_VERIFY_TLS -eq "true"

if (-not $Hostname) { throw "ZIC_HOST is required" }

$token = Get-ZicToken
$uri   = "$ApiBase/regions/$Region/resources/vms"
if ($TagName -and $TagValue) {
    $uri += "?tagName=$TagName&tagValue=$TagValue"
}

$params = @{
    Uri     = $uri
    Method  = "Get"
    Headers = @{
        "Authorization" = "Bearer $token"
        "Accept"        = "application/json"
    }
}
if (-not $VerifyTls) { $params["SkipCertificateCheck"] = $true }

$resp = Invoke-RestMethod @params
$vms  = $resp.vms

if (-not $vms -or $vms.Count -eq 0) {
    Write-Host "(no VMs in region $Region)"
    return
}

Write-Host "Region: $Region  ($($vms.Count) VMs)`n"

$vms | ForEach-Object {
    $props = $_.vmPropertiesModel
    $extra = $_.additionalPropertiesModel
    $vpgs  = if ($extra.protectedInVpgs) { ($extra.protectedInVpgs | ForEach-Object { $_.id }) -join "," } else { "-" }
    [PSCustomObject]@{
        vmId            = $props.id ?? $props.vmId
        name            = $props.name ?? $props.vmName
        protected       = $extra.isProtected
        protectedInVpgs = $vpgs
    }
} | Format-Table -AutoSize
