Set-StrictMode -Version Latest

if (-not (Get-Variable -Name RunnerJobs -Scope Script -ErrorAction SilentlyContinue)) {
    $script:RunnerJobs = @{}
}

function Add-RunnerJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptId,
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Job]$Job
    )

    $script:RunnerJobs[$Job.Id] = [pscustomobject]@{
        JobId      = $Job.Id
        ScriptId   = $ScriptId
        Name       = $Job.Name
        StartedAt  = Get-Date
        LastOutput = @()
    }
}

function Get-RunnerJobs {
    [CmdletBinding()]
    param()

    $result = @()
    foreach ($entry in $script:RunnerJobs.Values) {
        $job = Get-Job -Id $entry.JobId -ErrorAction SilentlyContinue
        $state = if ($job) { [string]$job.State } else { "Missing" }
        $result += [pscustomobject]@{
            JobId     = $entry.JobId
            ScriptId  = $entry.ScriptId
            Name      = $entry.Name
            StartedAt = $entry.StartedAt
            State     = $state
        }
    }
    return $result | Sort-Object -Property JobId
}

function Receive-RunnerJobOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$JobId
    )

    $job = Get-Job -Id $JobId -ErrorAction Stop
    $output = Receive-Job -Id $job.Id -Keep -ErrorAction Stop
    return $output
}
