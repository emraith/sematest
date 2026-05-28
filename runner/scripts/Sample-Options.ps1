#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("dev", "qa", "prod")]
    [string]$Environment,
    [Parameter(Mandatory = $true)]
    [securestring]$ApiToken,
    [Parameter(Mandatory = $false)]
    [bool]$DryRun = $true
)

$tokenLength = 0
if ($ApiToken) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ApiToken)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        $tokenLength = $plain.Length
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

Write-Output "Environment: $Environment"
Write-Output "DryRun: $DryRun"
Write-Output "ApiToken length: $tokenLength"
Write-Output "Options script completed."
