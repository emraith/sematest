#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [int]$Count,
    [Parameter(Mandatory = $false)]
    [bool]$VerboseMode = $false
)

Write-Output "Sample-Echo started."
Write-Output "Name: $Name"
Write-Output "Count: $Count"
Write-Output "VerboseMode: $VerboseMode"

for ($i = 1; $i -le $Count; $i++) {
    Write-Output "[$i/$Count] Hello, $Name"
}

if ($VerboseMode) {
    Write-Output "Verbose output enabled."
}

Write-Output "Sample-Echo complete."
