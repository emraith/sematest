#requires -Version 7.0
<#
.SYNOPSIS
    Appends a recovery suffix to hostnames listed in a VM list file and matching CSV rows.

.PARAMETER CsvFile
    Path to the input CSV export (must contain a hostname column).

.PARAMETER VmList
    Path to a text file with one hostname per line.

.PARAMETER Suffix
    Text appended to each matching hostname. Defaults to ' - testing recovery'.

.EXAMPLE
    .\Update-RecoveryHostnames.ps1 `
        -CsvFile .\va-export-20260528.csv `
        -VmList .\vmlist.txt
#>
param(
    [Parameter(Mandatory = $true)]
    [string]
    $CsvFile,

    [Parameter(Mandatory = $true)]
    [string]
    $VmList,

    [Parameter(Mandatory = $false)]
    [string]
    $Suffix = ' - testing recovery'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $CsvFile -PathType Leaf)) {
    throw "CSV file not found: $CsvFile"
}

if (-not (Test-Path -LiteralPath $VmList -PathType Leaf)) {
    throw "VM list file not found: $VmList"
}

$vmNames = @(Get-Content -LiteralPath $VmList |
    ForEach-Object { $_.Trim() } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

$vmLookup = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($name in $vmNames) {
    [void]$vmLookup.Add($name)
}

$rows = @(Import-Csv -LiteralPath $CsvFile)
$rowsUpdated = 0

foreach ($row in $rows) {
    if ($vmLookup.Contains($row.hostname)) {
        $row.hostname = $row.hostname + $Suffix
        $rowsUpdated++
    }
}

$csvOut = [System.IO.Path]::Combine(
    [System.IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $CsvFile).Path),
    ([System.IO.Path]::GetFileNameWithoutExtension($CsvFile) + '_recovery.csv')
)

$vmListOut = [System.IO.Path]::Combine(
    [System.IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $VmList).Path),
    ([System.IO.Path]::GetFileNameWithoutExtension($VmList) + '_recovery.txt')
)

$rows | Export-Csv -LiteralPath $csvOut -NoTypeInformation -Encoding utf8

$vmNames | ForEach-Object { $_ + $Suffix } | Set-Content -LiteralPath $vmListOut -Encoding utf8

Write-Host "Recovery hostname update complete."
Write-Host "  CSV rows updated: $rowsUpdated"
Write-Host "  CSV output:       $csvOut"
Write-Host "  VM list output:   $vmListOut"
