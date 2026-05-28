Set-StrictMode -Version Latest

function Resolve-RunnerScriptPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunnerRoot,
        [Parameter(Mandatory = $true)]
        [string]$RelativeScriptPath
    )

    $base = [System.IO.Path]::GetFullPath($RunnerRoot)
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $RunnerRoot $RelativeScriptPath))

    if (-not $candidate.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Script path escapes runner root: $RelativeScriptPath"
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "Script file not found: $candidate"
    }

    return $candidate
}

function Invoke-ConfiguredScriptForeground {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )

    $results = & $ScriptPath @Parameters 2>&1
    $exitCodeVar = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    $exitCode = if ($exitCodeVar) { [int]$exitCodeVar.Value } else { 0 }
    return [pscustomobject]@{
        Output   = $results
        ExitCode = $exitCode
    }
}

function Start-ConfiguredScriptBackground {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )

    $job = Start-Job -ScriptBlock {
        param($InnerScriptPath, $InnerParameters)
        & $InnerScriptPath @InnerParameters 2>&1
    } -ArgumentList $ScriptPath, $Parameters

    return $job
}
