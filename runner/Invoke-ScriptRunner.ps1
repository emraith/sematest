#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = (Join-Path $PSScriptRoot "config\scripts.json")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. (Join-Path $PSScriptRoot "core\ConfigLoader.ps1")
. (Join-Path $PSScriptRoot "core\FormRenderer.ps1")
. (Join-Path $PSScriptRoot "core\Executor.ps1")
. (Join-Path $PSScriptRoot "core\JobStore.ps1")

$config = Get-RunnerConfig -ConfigPath $ConfigPath
$runnerRoot = $PSScriptRoot

$form = New-Object System.Windows.Forms.Form
$form.Text = "PowerShell Script Runner"
$form.Width = 980
$form.Height = 700
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

$scriptsLabel = New-Object System.Windows.Forms.Label
$scriptsLabel.Text = "Scripts"
$scriptsLabel.Left = 10
$scriptsLabel.Top = 10
$scriptsLabel.Width = 120
$form.Controls.Add($scriptsLabel)

$scriptList = New-Object System.Windows.Forms.ListBox
$scriptList.Left = 10
$scriptList.Top = 30
$scriptList.Width = 260
$scriptList.Height = 560
$form.Controls.Add($scriptList)

$detailsLabel = New-Object System.Windows.Forms.Label
$detailsLabel.Text = "Details"
$detailsLabel.Left = 290
$detailsLabel.Top = 10
$detailsLabel.Width = 640
$form.Controls.Add($detailsLabel)

$detailsText = New-Object System.Windows.Forms.Label
$detailsText.Left = 290
$detailsText.Top = 30
$detailsText.Width = 650
$detailsText.Height = 45
$form.Controls.Add($detailsText)

$paramsPanel = New-Object System.Windows.Forms.Panel
$paramsPanel.Left = 290
$paramsPanel.Top = 80
$paramsPanel.Width = 660
$paramsPanel.Height = 250
$paramsPanel.AutoScroll = $true
$paramsPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($paramsPanel)

$modeLabel = New-Object System.Windows.Forms.Label
$modeLabel.Text = "Execution Mode"
$modeLabel.Left = 290
$modeLabel.Top = 340
$modeLabel.Width = 120
$form.Controls.Add($modeLabel)

$modeCombo = New-Object System.Windows.Forms.ComboBox
$modeCombo.Left = 420
$modeCombo.Top = 336
$modeCombo.Width = 140
$modeCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$modeCombo.Items.Add("foreground")
[void]$modeCombo.Items.Add("background")
$form.Controls.Add($modeCombo)

$runButton = New-Object System.Windows.Forms.Button
$runButton.Text = "Run Script"
$runButton.Left = 580
$runButton.Top = 334
$runButton.Width = 110
$form.Controls.Add($runButton)

$refreshJobsButton = New-Object System.Windows.Forms.Button
$refreshJobsButton.Text = "Refresh Jobs"
$refreshJobsButton.Left = 700
$refreshJobsButton.Top = 334
$refreshJobsButton.Width = 110
$form.Controls.Add($refreshJobsButton)

$receiveJobButton = New-Object System.Windows.Forms.Button
$receiveJobButton.Text = "Receive Output"
$receiveJobButton.Left = 820
$receiveJobButton.Top = 334
$receiveJobButton.Width = 120
$form.Controls.Add($receiveJobButton)

$outputLabel = New-Object System.Windows.Forms.Label
$outputLabel.Text = "Output / Status"
$outputLabel.Left = 290
$outputLabel.Top = 370
$outputLabel.Width = 150
$form.Controls.Add($outputLabel)

$outputText = New-Object System.Windows.Forms.TextBox
$outputText.Left = 290
$outputText.Top = 390
$outputText.Width = 660
$outputText.Height = 200
$outputText.Multiline = $true
$outputText.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$outputText.ReadOnly = $true
$form.Controls.Add($outputText)

$jobsList = New-Object System.Windows.Forms.ListBox
$jobsList.Left = 10
$jobsList.Top = 600
$jobsList.Width = 940
$jobsList.Height = 60
$form.Controls.Add($jobsList)

$scriptIndex = @{}
foreach ($entry in $config.scripts) {
    $display = "$($entry.label) [$($entry.id)]"
    [void]$scriptList.Items.Add($display)
    $scriptIndex[$display] = $entry
}

$script:CurrentControlMap = @{}
$script:CurrentScript = $null

function Set-OutputText {
    param([string]$Message)
    $outputText.Text = $Message
}

function Refresh-JobListUi {
    $jobsList.Items.Clear()
    $jobs = Get-RunnerJobs
    foreach ($job in $jobs) {
        $line = "Job $($job.JobId) | $($job.ScriptId) | $($job.State) | $($job.StartedAt)"
        [void]$jobsList.Items.Add($line)
    }
}

$scriptList.add_SelectedIndexChanged({
    if ($scriptList.SelectedItem -eq $null) { return }

    $selected = [string]$scriptList.SelectedItem
    $script:CurrentScript = $scriptIndex[$selected]

    $detailsText.Text = [string]$script:CurrentScript.description
    $script:CurrentControlMap = New-ParameterControls -Panel $paramsPanel -Parameters $script:CurrentScript.parameters
    Initialize-DerivedDisplays -ControlMap $script:CurrentControlMap -RunnerRoot $runnerRoot

    $modeCombo.SelectedItem = [string]$script:CurrentScript.defaultMode
    if (-not $script:CurrentScript.allowModeOverride) {
        $modeCombo.Enabled = $false
    } else {
        $modeCombo.Enabled = $true
    }
})

$runButton.add_Click({
    if ($null -eq $script:CurrentScript) {
        [System.Windows.Forms.MessageBox]::Show("Select a script first.") | Out-Null
        return
    }

    try {
        $paramValues = Get-ParameterValues -ControlMap $script:CurrentControlMap
        $scriptPath = Resolve-RunnerScriptPath -RunnerRoot $runnerRoot -RelativeScriptPath ([string]$script:CurrentScript.path)
        $mode = [string]$modeCombo.SelectedItem
        if ([string]::IsNullOrWhiteSpace($mode)) {
            $mode = [string]$script:CurrentScript.defaultMode
        }

        Set-OutputText "Running '$($script:CurrentScript.label)' in $mode mode..."

        if ($mode -eq "background") {
            $job = Start-ConfiguredScriptBackground -ScriptPath $scriptPath -Parameters $paramValues
            Add-RunnerJob -ScriptId ([string]$script:CurrentScript.id) -Job $job
            Set-OutputText "Started background job ID: $($job.Id)"
            Refresh-JobListUi
        } else {
            $result = Invoke-ConfiguredScriptForeground -ScriptPath $scriptPath -Parameters $paramValues
            $lines = @()
            foreach ($record in $result.Output) {
                $lines += [string]$record
            }
            $joined = $lines -join [Environment]::NewLine
            Set-OutputText ($joined + [Environment]::NewLine + "ExitCode: $($result.ExitCode)")
        }
    } catch {
        Set-OutputText "ERROR: $($_.Exception.Message)"
    }
})

$refreshJobsButton.add_Click({
    try {
        Refresh-JobListUi
    } catch {
        Set-OutputText "ERROR refreshing jobs: $($_.Exception.Message)"
    }
})

$receiveJobButton.add_Click({
    if ($jobsList.SelectedItem -eq $null) {
        [System.Windows.Forms.MessageBox]::Show("Select a job line first.") | Out-Null
        return
    }

    $line = [string]$jobsList.SelectedItem
    if ($line -notmatch "^Job (\d+) \|") {
        Set-OutputText "Could not parse selected job."
        return
    }

    $jobId = [int]$Matches[1]
    try {
        $output = Receive-RunnerJobOutput -JobId $jobId
        $text = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($text)) {
            $text = "(no output yet)"
        }
        Set-OutputText $text
        Refresh-JobListUi
    } catch {
        Set-OutputText "ERROR receiving job output: $($_.Exception.Message)"
    }
})

if ($scriptList.Items.Count -gt 0) {
    $scriptList.SelectedIndex = 0
}

[void]$form.ShowDialog()
