# ─────────────────────────────────────────────────────────────────────────
# Get an OAuth bearer token from the ZIC appliance's Keycloak.
# Writes the access_token to stdout. Requires PowerShell 7+ for
# -SkipCertificateCheck. Other examples dot-source this file.
# ─────────────────────────────────────────────────────────────────────────

function Get-ZicToken {
    [CmdletBinding()]
    param(
        [string]$Hostname   = $env:ZIC_HOST,
        [string]$Username   = $env:ZIC_USERNAME,
        [string]$Password   = $env:ZIC_PASSWORD,
        [string]$TokenUrl   = $env:ZIC_TOKEN_URL,
        [string]$ClientId   = $(if ($env:ZIC_CLIENT_ID) { $env:ZIC_CLIENT_ID } else { "zerto-client" }),
        [bool]  $VerifyTls  = $(if ($env:ZIC_VERIFY_TLS -eq "true") { $true } else { $false })
    )

    if (-not $Hostname) { throw "ZIC_HOST is required (set env var or pass -Hostname)" }
    if (-not $Username) { throw "ZIC_USERNAME is required" }
    if (-not $Password) { throw "ZIC_PASSWORD is required" }

    if (-not $TokenUrl) {
        $TokenUrl = "https://$Hostname/auth/realms/zerto/protocol/openid-connect/token"
    }

    $body = @{
        grant_type = "password"
        scope      = "openid"
        client_id  = $ClientId
        username   = $Username
        password   = $Password
    }

    $params = @{
        Uri         = $TokenUrl
        Method      = "Post"
        Body        = $body
        ContentType = "application/x-www-form-urlencoded"
    }
    if (-not $VerifyTls) { $params["SkipCertificateCheck"] = $true }

    $response = Invoke-RestMethod @params

    if (-not $response.access_token) {
        throw "no access_token in response: $($response | ConvertTo-Json -Depth 5)"
    }
    return $response.access_token
}

# When invoked as a script (not dot-sourced), print the token.
if ($MyInvocation.InvocationName -ne '.') {
    try {
        Get-ZicToken
    } catch {
        Write-Error $_
        exit 1
    }
}
