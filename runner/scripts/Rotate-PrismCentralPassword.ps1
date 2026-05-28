#requires -Version 7.0

<#
.SYNOPSIS
    Rotates a Nutanix Prism Central user password for a selected site.

.DESCRIPTION
    Resolves a friendly location name (Virginia, Texas, Amsterdam) to a Prism Central
    hostname via runner\config\PrismCentralSites.json, then performs password rotation.

    API call logic is stubbed; wire Invoke-PrismCentralPasswordChangeApi when ready.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Virginia", "Texas", "Amsterdam")]
    [string]$Location,

    [Parameter(Mandatory = $false)]
    [string]$Username = "admin",

    [Parameter(Mandatory = $true)]
    [securestring]$CurrentPassword,

    [Parameter(Mandatory = $true)]
    [securestring]$NewPassword,

    [Parameter(Mandatory = $false)]
    [bool]$SkipCertificateCheck = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-PlainTextFromSecureString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [securestring]$SecureString
    )

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Get-PrismCentralSiteMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SitesConfigPath
    )

    if (-not (Test-Path -LiteralPath $SitesConfigPath -PathType Leaf)) {
        throw "Prism Central site map not found: $SitesConfigPath"
    }

    $raw = Get-Content -LiteralPath $SitesConfigPath -Raw
    $config = $raw | ConvertFrom-Json -Depth 5

    $map = @{}
    foreach ($site in $config.sites) {
        $map[[string]$site.location] = [string]$site.hostname
    }
    return $map
}

function Invoke-PrismCentralPasswordChangeApi {
    <#
    .SYNOPSIS
        Calls Prism Central to change the user password.

    .NOTES
        Replace this stub with your existing API implementation.
        Typical inputs: BaseUrl, Username, CurrentPassword, NewPassword, SkipCertificateCheck
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,
        [Parameter(Mandatory = $true)]
        [string]$Username,
        [Parameter(Mandatory = $true)]
        [string]$CurrentPassword,
        [Parameter(Mandatory = $true)]
        [string]$NewPassword,
        [Parameter(Mandatory = $false)]
        [bool]$SkipCertificateCheck = $false
    )

    Write-Output "[API stub] Would authenticate to $BaseUrl as '$Username'."
    Write-Output "[API stub] Would submit password change request for user '$Username'."
    Write-Output "[API stub] SkipCertificateCheck: $SkipCertificateCheck"

    # Example hook (uncomment and adapt to your API details):
    # $session = Connect-PrismCentralSession -BaseUrl $BaseUrl -Username $Username -Password $CurrentPassword -SkipCertificateCheck:$SkipCertificateCheck
    # Set-PrismCentralUserPassword -Session $session -Username $Username -NewPassword $NewPassword
}

$sitesConfigPath = Join-Path $PSScriptRoot "..\config\PrismCentralSites.json"
$siteMap = Get-PrismCentralSiteMap -SitesConfigPath $sitesConfigPath

if (-not $siteMap.ContainsKey($Location)) {
    throw "Unknown location '$Location'. Update PrismCentralSites.json."
}

$hostname = $siteMap[$Location]
$baseUrl = "https://${hostname}:9440"

$currentPlain = ConvertTo-PlainTextFromSecureString -SecureString $CurrentPassword
$newPlain = ConvertTo-PlainTextFromSecureString -SecureString $NewPassword

if ([string]::IsNullOrWhiteSpace($currentPlain)) {
    throw "Current password cannot be empty."
}
if ([string]::IsNullOrWhiteSpace($newPlain)) {
    throw "New password cannot be empty."
}
if ($currentPlain -ceq $newPlain) {
    throw "New password must be different from the current password."
}

Write-Output "Password Rotation - Nutanix Prism Central"
Write-Output "Location:   $Location"
Write-Output "Hostname:   $hostname"
Write-Output "Base URL:   $baseUrl"
Write-Output "Username:   $Username"
Write-Output "Started:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

try {
    Invoke-PrismCentralPasswordChangeApi `
        -BaseUrl $baseUrl `
        -Username $Username `
        -CurrentPassword $currentPlain `
        -NewPassword $newPlain `
        -SkipCertificateCheck:$SkipCertificateCheck

    Write-Output "Completed:  Password rotation request finished for '$Username' at $Location ($hostname)."
} catch {
    Write-Error "Password rotation failed for '$Username' at $Location ($hostname): $($_.Exception.Message)"
    throw
}
