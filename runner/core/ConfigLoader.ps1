Set-StrictMode -Version Latest

function Get-RunnerConfigProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) {
        return $prop.Value
    }
    return $null
}

function Get-RunnerConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Config file not found: $ConfigPath"
    }

    try {
        $raw = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop
        $config = $raw | ConvertFrom-Json -Depth 10 -ErrorAction Stop
    } catch {
        throw "Unable to parse config JSON at '$ConfigPath'. $($_.Exception.Message)"
    }

    if (-not $config.scripts -or $config.scripts.Count -eq 0) {
        throw "Config must contain a non-empty 'scripts' array."
    }

    foreach ($script in $config.scripts) {
        if ([string]::IsNullOrWhiteSpace($script.id)) { throw "Each script entry requires 'id'." }
        if ([string]::IsNullOrWhiteSpace($script.label)) { throw "Script '$($script.id)' requires 'label'." }
        if ([string]::IsNullOrWhiteSpace($script.path)) { throw "Script '$($script.id)' requires 'path'." }
        if ([string]::IsNullOrWhiteSpace($script.defaultMode)) { $script.defaultMode = "foreground" }

        if ($script.defaultMode -notin @("foreground", "background")) {
            throw "Script '$($script.id)' has invalid defaultMode '$($script.defaultMode)'."
        }

        if ($null -eq $script.allowModeOverride) {
            $script | Add-Member -NotePropertyName allowModeOverride -NotePropertyValue $true
        }

        if ($null -eq $script.parameters) {
            $script | Add-Member -NotePropertyName parameters -NotePropertyValue @()
        }

        foreach ($parameter in $script.parameters) {
            if ([string]::IsNullOrWhiteSpace($parameter.name)) {
                throw "Script '$($script.id)' has a parameter missing 'name'."
            }
            if ([string]::IsNullOrWhiteSpace($parameter.type)) {
                $parameter.type = "string"
            }
            if ($parameter.type -notin @("string", "int", "bool", "choice", "securestring", "display")) {
                throw "Script '$($script.id)' parameter '$($parameter.name)' has unsupported type '$($parameter.type)'."
            }
            if ($parameter.type -eq "choice" -and (-not $parameter.choices -or $parameter.choices.Count -eq 0)) {
                throw "Script '$($script.id)' parameter '$($parameter.name)' type 'choice' requires choices."
            }
            if ($parameter.type -eq "display") {
                if ([string]::IsNullOrWhiteSpace((Get-RunnerConfigProperty -Object $parameter -Name 'deriveFrom'))) {
                    throw "Script '$($script.id)' parameter '$($parameter.name)' type 'display' requires deriveFrom."
                }
                if ([string]::IsNullOrWhiteSpace((Get-RunnerConfigProperty -Object $parameter -Name 'lookupFile'))) {
                    throw "Script '$($script.id)' parameter '$($parameter.name)' type 'display' requires lookupFile."
                }
            }
        }
    }

    return $config
}
