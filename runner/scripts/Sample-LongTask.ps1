#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TaskName,
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 30)]
    [int]$Seconds
)

Write-Output "Starting long task '$TaskName' for about $Seconds second(s)."

for ($i = 1; $i -le $Seconds; $i++) {
    Write-Output "[$TaskName] step $i of $Seconds"
    Start-Sleep -Seconds 1
}

Write-Output "Long task '$TaskName' completed."
