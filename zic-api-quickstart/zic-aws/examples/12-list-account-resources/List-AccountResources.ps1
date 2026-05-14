# ─────────────────────────────────────────────────────────────────────────
# Multiplexing CLI for v2's account-scoped resource discovery endpoints.
#
# Usage:
#   ./List-AccountResources.ps1 -AccountId <id> -Resource regions
#   ./List-AccountResources.ps1 -AccountId <id> -Resource vms          -RegionId us-east-1
#   ./List-AccountResources.ps1 -AccountId <id> -Resource vnets        -RegionId us-east-1
#   ./List-AccountResources.ps1 -AccountId <id> -Resource subnets      -RegionId us-east-1 -VnetId vpc-...
#   ./List-AccountResources.ps1 -AccountId <id> -Resource sgroups      -RegionId us-east-1 -VnetId vpc-...
#   ./List-AccountResources.ps1 -AccountId <id> -Resource keypairs     -RegionId us-east-1
#   ./List-AccountResources.ps1 -AccountId <id> -Resource cmks         -RegionId us-east-1
#   ./List-AccountResources.ps1 -AccountId <id> -Resource launchtemplates -RegionId us-east-1
#   ./List-AccountResources.ps1 -AccountId <id> -Resource roles
# ─────────────────────────────────────────────────────────────────────────

param(
    [Parameter(Mandatory=$true)]
    [string]$AccountId,

    [Parameter(Mandatory=$true)]
    [ValidateSet("regions","vms","vnets","subnets","sgroups","keypairs","cmks","launchtemplates","roles")]
    [string]$Resource,

    [string]$RegionId,
    [string]$VnetId,
    [string]$TagName,
    [string]$TagValue
)

. "$PSScriptRoot/../01-get-token/Get-Token.ps1"

$Hostname  = $env:ZIC_HOST
$V2Base    = "https://$Hostname/zic/api/v2"
$VerifyTls = $env:ZIC_VERIFY_TLS -eq "true"

if (-not $Hostname) { throw "ZIC_HOST is required" }

$base = "$V2Base/accounts/$AccountId"

$url = switch ($Resource) {
    "regions"          { "$base/regions" }
    "vms"              {
        if (-not $RegionId) { throw "vms requires -RegionId" }
        $u = "$base/regions/$RegionId/resources/vms"
        if ($TagName -and $TagValue) { $u += "?tagName=$TagName&tagValue=$TagValue" }
        $u
    }
    "vnets"            {
        if (-not $RegionId) { throw "vnets requires -RegionId" }
        "$base/regions/$RegionId/resources/vnets"
    }
    "subnets"          {
        if (-not $RegionId -or -not $VnetId) { throw "subnets requires -RegionId and -VnetId" }
        "$base/regions/$RegionId/resources/vnets/$VnetId/subnets"
    }
    "sgroups"          {
        if (-not $RegionId -or -not $VnetId) { throw "sgroups requires -RegionId and -VnetId" }
        "$base/regions/$RegionId/resources/vnets/$VnetId/sgroups"
    }
    "keypairs"         {
        if (-not $RegionId) { throw "keypairs requires -RegionId" }
        "$base/regions/$RegionId/resources/keypairs"
    }
    "cmks"             {
        if (-not $RegionId) { throw "cmks requires -RegionId" }
        "$base/regions/$RegionId/resources/cmks"
    }
    "launchtemplates"  {
        if (-not $RegionId) { throw "launchtemplates requires -RegionId" }
        "$base/regions/$RegionId/resources/launchtemplates"
    }
    "roles"            { "$base/resources/roles" }
}

$token = Get-ZicToken
$params = @{
    Uri     = $url
    Method  = "Get"
    Headers = @{
        "Authorization" = "Bearer $token"
        "Accept"        = "application/json"
    }
}
if (-not $VerifyTls) { $params["SkipCertificateCheck"] = $true }

Write-Host "→ GET    $url"
$resp = Invoke-RestMethod @params

# Resource-specific summary printers
switch ($Resource) {
    "regions"          { $resp.regions          | Format-Table id,name -AutoSize }
    "vms"              {
        $resp.vms | ForEach-Object {
            [PSCustomObject]@{
                vmId      = $_.vmPropertiesModel.id
                name      = $_.vmPropertiesModel.name
                protected = $_.additionalPropertiesModel.isProtected
            }
        } | Format-Table -AutoSize
    }
    "vnets"            { $resp.vnets            | Format-Table -AutoSize }
    "subnets"          { $resp.subnets          | Format-Table -AutoSize }
    "sgroups"          { $resp.sgroups          | Format-Table -AutoSize }
    "keypairs"         { $resp.keypairs         | Format-Table -AutoSize }
    "cmks"             { $resp.cmks             | Format-Table -AutoSize }
    "launchtemplates"  { $resp.launchTemplates  | Format-Table -AutoSize }
    "roles"            { $resp.roles            | Format-Table -AutoSize }
}
