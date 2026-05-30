# CSV Export Cleanup

[`Invoke-CsvExportCleanup.ps1`](Invoke-CsvExportCleanup.ps1) runs after the nightly tag CSV exports finish. It keeps recent export files in the reports folder and removes older ones.

## What it does

1. **Retention cleanup** — Deletes export CSV files older than the retention window (default: 3 calendar days, including today). Files must match the naming pattern `{site}-export-{YYYYMMDD}.csv` (for example, `tx-export-20260529.csv`).

2. **Empty export check** — For today's exports only, checks whether the file contains just a header row (or is empty). If so, it calls `Send-EmptyExportAlert`, which is currently a placeholder you can replace with real email logic.

By default, the script looks in the `reports` folder next to the script. Use `-ReportsPath` to point at your production export directory.

## Requirements

- PowerShell 7 or newer (`pwsh`)

## Usage

Run manually:

```powershell
pwsh -File "C:\Code2\script_runner\csv_cleanup\Invoke-CsvExportCleanup.ps1"
```

Preview changes without deleting files:

```powershell
pwsh -File "C:\Code2\script_runner\csv_cleanup\Invoke-CsvExportCleanup.ps1" -WhatIf -Verbose
```

Custom reports path or retention:

```powershell
pwsh -File "C:\Code2\script_runner\csv_cleanup\Invoke-CsvExportCleanup.ps1" `
  -ReportsPath "D:\exports\reports" `
  -RetentionDays 3
```

## Scheduled task example

Schedule this to run **after** the nightly export task completes. Adjust the time and paths for your environment.

```powershell
$scriptPath = 'C:\Code2\script_runner\csv_cleanup\Invoke-CsvExportCleanup.ps1'
$reportsPath = 'C:\Code2\script_runner\csv_cleanup\reports'

$action = New-ScheduledTaskAction `
  -Execute 'pwsh.exe' `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -ReportsPath `"$reportsPath`""

$trigger = New-ScheduledTaskTrigger -Daily -At '2:30AM'

Register-ScheduledTask `
  -TaskName 'CSV Export Cleanup' `
  -Action $action `
  -Trigger $trigger `
  -Description 'Remove old tag export CSVs and alert on empty daily exports.'
```

To remove the task later:

```powershell
Unregister-ScheduledTask -TaskName 'CSV Export Cleanup' -Confirm:$false
```
