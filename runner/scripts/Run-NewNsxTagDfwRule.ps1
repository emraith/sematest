#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TagName,
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,
    [Parameter(Mandatory = $true)]
    [string]$Username,
    [Parameter(Mandatory = $true)]
    [securestring]$Password,
    [Parameter(Mandatory = $false)]
    [ValidateSet("Local", "Global")]
    [string]$ManagerType = "Local",
    [Parameter(Mandatory = $false)]
    [string]$DomainId = "default",
    [Parameter(Mandatory = $false)]
    [string]$PolicyName,
    [Parameter(Mandatory = $false)]
    [string]$PolicyPath,
    [Parameter(Mandatory = $false)]
    [string]$Description,
    [Parameter(Mandatory = $false)]
    [string]$RitmNumber,
    [Parameter(Mandatory = $false)]
    [string]$ServiceNamesCsv = "MS_SQL_Services",
    [Parameter(Mandatory = $false)]
    [ValidateSet("ALLOW", "DROP", "REJECT", "JUMP_TO_APPLICATION")]
    [string]$Action = "ALLOW",
    [Parameter(Mandatory = $false)]
    [ValidateSet("IN", "OUT", "IN_OUT")]
    [string]$Direction = "IN_OUT",
    [Parameter(Mandatory = $false)]
    [bool]$Logged = $true,
    [Parameter(Mandatory = $false)]
    [bool]$SkipCertificateCheck = $false
)

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$targetScript = Join-Path $root "New-NsxTagDfwRule.ps1"

if (-not (Test-Path -LiteralPath $targetScript -PathType Leaf)) {
    throw "Target script not found: $targetScript"
}

$credential = [pscredential]::new($Username, $Password)
$serviceNames = @(
    $ServiceNamesCsv -split "," | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($serviceNames.Count -eq 0) {
    $serviceNames = @("MS_SQL_Services")
}

$invokeParams = @{
    TagName      = $TagName
    BaseUrl      = $BaseUrl
    Credential   = $credential
    ManagerType  = $ManagerType
    DomainId     = $DomainId
    ServiceNames = $serviceNames
    Action       = $Action
    Direction    = $Direction
    Logged       = $Logged
}

if (-not [string]::IsNullOrWhiteSpace($PolicyName)) { $invokeParams.PolicyName = $PolicyName }
if (-not [string]::IsNullOrWhiteSpace($PolicyPath)) { $invokeParams.PolicyPath = $PolicyPath }
if (-not [string]::IsNullOrWhiteSpace($Description)) { $invokeParams.Description = $Description }
if (-not [string]::IsNullOrWhiteSpace($RitmNumber)) { $invokeParams.RitmNumber = $RitmNumber }
if ($SkipCertificateCheck) { $invokeParams.SkipCertificateCheck = $true }

& $targetScript @invokeParams
