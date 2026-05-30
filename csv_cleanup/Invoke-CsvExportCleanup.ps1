#requires -Version 7.0
<#
.SYNOPSIS
    Cleans up nightly CSV export files and alerts on empty exports.

.DESCRIPTION
    Removes export CSV files older than the retention window from the reports folder.
    For today's exports, checks whether the file contains only a header row (or is empty)
    and calls Send-EmptyExportAlert when no data rows are present.

.PARAMETER ReportsPath
    Folder containing nightly export CSV files.

.PARAMETER RetentionDays
    Number of calendar days of exports to keep, inclusive of the reference date.

.PARAMETER ReferenceDate
    Date used for retention cutoff and today's export validation. Defaults to today.

.EXAMPLE
    .\Invoke-CsvExportCleanup.ps1

.EXAMPLE
    .\Invoke-CsvExportCleanup.ps1 -WhatIf -Verbose

.EXAMPLE
    .\Invoke-CsvExportCleanup.ps1 -ReferenceDate '2026-05-30' -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string]
    $ReportsPath = (Join-Path $PSScriptRoot 'reports'),

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]
    $RetentionDays = 3,

    [Parameter(Mandatory = $false)]
    [datetime]
    $ReferenceDate = (Get-Date).Date
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-CsvHeaderOnly {
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $LiteralPath
    )

    $nonEmptyLines = @(Get-Content -LiteralPath $LiteralPath |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    return $nonEmptyLines.Count -le 1
}

function Send-EmptyExportAlert {
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $FilePath,

        [Parameter(Mandatory = $true)]
        [string]
        $Site,

        [Parameter(Mandatory = $true)]
        [datetime]
        $ExportDate
    )

    Write-Warning "Empty export alert placeholder: site=$Site date=$($ExportDate.ToString('yyyy-MM-dd')) file=$FilePath"
}

$exportFilePattern = '^(?<site>.+)-export-(?<date>\d{8})\.csv$'
$referenceDay = $ReferenceDate.Date
$cutoffDate = $referenceDay.AddDays(1 - $RetentionDays)

if (-not (Test-Path -LiteralPath $ReportsPath -PathType Container)) {
    throw "Reports path not found: $ReportsPath"
}

Write-Verbose "ReportsPath: $ReportsPath"
Write-Verbose "ReferenceDate: $($referenceDay.ToString('yyyy-MM-dd'))"
Write-Verbose "RetentionDays: $RetentionDays"
Write-Verbose "CutoffDate: $($cutoffDate.ToString('yyyy-MM-dd')) (files before this date will be removed)"

$filesScanned = 0
$filesDeleted = 0
$filesKept = 0
$filesSkipped = 0
$alertsSent = 0

Get-ChildItem -LiteralPath $ReportsPath -Filter '*.csv' -File |
    Sort-Object Name |
    ForEach-Object {
        $filesScanned++
        $file = $_

        if ($file.Name -notmatch $exportFilePattern) {
            Write-Warning "Skipping file with unexpected name: $($file.Name)"
            $filesSkipped++
            return
        }

        $site = $Matches['site']
        $exportDate = [datetime]::ParseExact($Matches['date'], 'yyyyMMdd', $null)

        if ($exportDate -lt $cutoffDate) {
            if ($PSCmdlet.ShouldProcess($file.FullName, 'Remove expired export file')) {
                Remove-Item -LiteralPath $file.FullName -Force
                Write-Verbose "Deleted: $($file.Name)"
            }
            else {
                Write-Verbose "Would delete: $($file.Name)"
            }

            $filesDeleted++
            return
        }

        $filesKept++

        if ($exportDate -eq $referenceDay) {
            Write-Verbose "Checking today's export for data rows: $($file.Name)"

            if (Test-CsvHeaderOnly -LiteralPath $file.FullName) {
                Send-EmptyExportAlert -FilePath $file.FullName -Site $site -ExportDate $exportDate
                $alertsSent++
            }
        }
    }

Write-Host "CSV export cleanup complete."
Write-Host "  Files scanned:  $filesScanned"
Write-Host "  Files deleted:  $filesDeleted"
Write-Host "  Files kept:     $filesKept"
Write-Host "  Files skipped:  $filesSkipped"
Write-Host "  Alerts sent:    $alertsSent"
