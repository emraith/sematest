Set-StrictMode -Version Latest

function Get-ConfigProperty {
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

function Get-LookupMapFromFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunnerRoot,
        [Parameter(Mandatory = $true)]
        [string]$LookupFile,
        [Parameter(Mandatory = $false)]
        [string]$ArrayProperty = "sites",
        [Parameter(Mandatory = $true)]
        [string]$MatchProperty,
        [Parameter(Mandatory = $true)]
        [string]$ValueProperty
    )

    $lookupPath = [System.IO.Path]::GetFullPath((Join-Path $RunnerRoot $LookupFile))
    $runnerBase = [System.IO.Path]::GetFullPath($RunnerRoot)
    if (-not $lookupPath.StartsWith($runnerBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Lookup file escapes runner root: $LookupFile"
    }
    if (-not (Test-Path -LiteralPath $lookupPath -PathType Leaf)) {
        throw "Lookup file not found: $lookupPath"
    }

    $raw = Get-Content -LiteralPath $lookupPath -Raw
    $config = $raw | ConvertFrom-Json -Depth 5
    $items = $config.$ArrayProperty
    if (-not $items) {
        throw "Lookup file '$LookupFile' is missing array property '$ArrayProperty'."
    }

    $map = @{}
    foreach ($item in $items) {
        $key = [string]$item.$MatchProperty
        $value = [string]$item.$ValueProperty
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $map[$key] = $value
        }
    }
    return $map
}

function Initialize-DerivedDisplays {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ControlMap,
        [Parameter(Mandatory = $true)]
        [string]$RunnerRoot
    )

    foreach ($name in $ControlMap.Keys) {
        $entry = $ControlMap[$name]
        $definition = $entry.Definition
        if ([string]$definition.type -ne "display") {
            continue
        }

        $deriveFrom = [string](Get-ConfigProperty -Object $definition -Name 'deriveFrom')
        $lookupFile = [string](Get-ConfigProperty -Object $definition -Name 'lookupFile')
        $arrayProperty = [string](Get-ConfigProperty -Object $definition -Name 'lookupArrayProperty')
        $matchProperty = [string](Get-ConfigProperty -Object $definition -Name 'lookupMatchProperty')
        $valueProperty = [string](Get-ConfigProperty -Object $definition -Name 'lookupValueProperty')

        if ([string]::IsNullOrWhiteSpace($arrayProperty)) { $arrayProperty = "sites" }
        if ([string]::IsNullOrWhiteSpace($matchProperty)) { $matchProperty = "location" }
        if ([string]::IsNullOrWhiteSpace($valueProperty)) { $valueProperty = "hostname" }

        if (-not $ControlMap.ContainsKey($deriveFrom)) {
            throw "Display parameter '$name' references unknown deriveFrom '$deriveFrom'."
        }

        $sourceControl = $ControlMap[$deriveFrom].Control
        if ($sourceControl -isnot [System.Windows.Forms.ComboBox]) {
            throw "Display parameter '$name' deriveFrom '$deriveFrom' must be a choice dropdown."
        }

        $displayControl = $entry.Control
        $lookupMap = Get-LookupMapFromFile `
            -RunnerRoot $RunnerRoot `
            -LookupFile $lookupFile `
            -ArrayProperty $arrayProperty `
            -MatchProperty $matchProperty `
            -ValueProperty $valueProperty

        $sourceControl.Tag = @{
            DisplayControl = $displayControl
            LookupMap      = $lookupMap
        }

        Update-DerivedDisplayControl -SourceCombo $sourceControl
        $sourceControl.Add_SelectedIndexChanged({
            Update-DerivedDisplayControl -SourceCombo $this
        })
    }
}

function Update-DerivedDisplayControl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.ComboBox]$SourceCombo
    )

    $ctx = $SourceCombo.Tag
    if (-not $ctx) {
        return
    }

    $selected = [string]$SourceCombo.SelectedItem
    if ([string]::IsNullOrWhiteSpace($selected) -or -not $ctx.LookupMap.ContainsKey($selected)) {
        $ctx.DisplayControl.Text = ""
        return
    }

    $ctx.DisplayControl.Text = [string]$ctx.LookupMap[$selected]
}

function New-ParameterControls {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Panel]$Panel,
        [Parameter(Mandatory = $true)]
        [object[]]$Parameters
    )

    $Panel.Controls.Clear()
    $controls = @{}
    $top = 8

    foreach ($parameter in $Parameters) {
        $defaultValue = Get-ConfigProperty -Object $parameter -Name 'default'
        $helpText = Get-ConfigProperty -Object $parameter -Name 'helpText'
        $isRequired = [bool](Get-ConfigProperty -Object $parameter -Name 'required')

        $label = New-Object System.Windows.Forms.Label
        $requiredMark = if ($isRequired) { " *" } else { "" }
        $label.Text = "$($parameter.name)$requiredMark"
        $label.Left = 8
        $label.Top = $top + 4
        $label.Width = 180
        $Panel.Controls.Add($label)

        $control = $null
        switch ($parameter.type) {
            "bool" {
                $control = New-Object System.Windows.Forms.CheckBox
                $control.Left = 200
                $control.Top = $top
                $control.Width = 300
                if ($null -ne $defaultValue) {
                    $control.Checked = [bool]$defaultValue
                }
            }
            "choice" {
                $control = New-Object System.Windows.Forms.ComboBox
                $control.Left = 200
                $control.Top = $top
                $control.Width = 320
                $control.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
                foreach ($choice in $parameter.choices) {
                    [void]$control.Items.Add([string]$choice)
                }
                if ($null -ne $defaultValue -and -not [string]::IsNullOrWhiteSpace([string]$defaultValue)) {
                    $idx = $control.Items.IndexOf([string]$defaultValue)
                    if ($idx -ge 0) { $control.SelectedIndex = $idx }
                } elseif ($control.Items.Count -gt 0) {
                    $control.SelectedIndex = 0
                }
            }
            "securestring" {
                $control = New-Object System.Windows.Forms.TextBox
                $control.Left = 200
                $control.Top = $top
                $control.Width = 320
                $control.UseSystemPasswordChar = $true
            }
            "display" {
                $control = New-Object System.Windows.Forms.TextBox
                $control.Left = 200
                $control.Top = $top
                $control.Width = 320
                $control.ReadOnly = $true
                $control.TabStop = $false
                $control.BackColor = [System.Drawing.SystemColors]::Control
            }
            Default {
                $control = New-Object System.Windows.Forms.TextBox
                $control.Left = 200
                $control.Top = $top
                $control.Width = 320
                if ($null -ne $defaultValue) {
                    $control.Text = [string]$defaultValue
                }
            }
        }

        $Panel.Controls.Add($control)
        $controls[$parameter.name] = [pscustomobject]@{
            Definition = $parameter
            Control    = $control
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$helpText)) {
            $help = New-Object System.Windows.Forms.Label
            $help.Text = [string]$helpText
            $help.Left = 200
            $help.Top = $top + 26
            $help.Width = 500
            $help.ForeColor = [System.Drawing.Color]::DimGray
            $Panel.Controls.Add($help)
            $top += 50
        } else {
            $top += 34
        }
    }

    return $controls
}

function Get-ParameterValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ControlMap
    )

    $values = @{}

    foreach ($name in $ControlMap.Keys) {
        $entry = $ControlMap[$name]
        $definition = $entry.Definition
        $control = $entry.Control
        $type = [string]$definition.type

        if ($type -eq "display") {
            continue
        }

        $value = switch ($type) {
            "bool" { [bool]$control.Checked }
            "choice" { [string]$control.SelectedItem }
            "securestring" { ConvertTo-SecureString -String $control.Text -AsPlainText -Force }
            Default { $control.Text }
        }

        $isRequired = [bool](Get-ConfigProperty -Object $definition -Name 'required')
        $minValue = Get-ConfigProperty -Object $definition -Name 'min'
        $maxValue = Get-ConfigProperty -Object $definition -Name 'max'
        $pattern = Get-ConfigProperty -Object $definition -Name 'pattern'

        if ($isRequired) {
            $missing = $false
            if ($type -eq "bool") {
                $missing = $false
            } elseif ($type -eq "choice") {
                $missing = [string]::IsNullOrWhiteSpace([string]$value)
            } else {
                $missing = [string]::IsNullOrWhiteSpace([string]$control.Text)
            }
            if ($missing) {
                throw "Parameter '$name' is required."
            }
        }

        if ($type -eq "int" -and -not [string]::IsNullOrWhiteSpace([string]$control.Text)) {
            $parsed = 0
            if (-not [int]::TryParse($control.Text, [ref]$parsed)) {
                throw "Parameter '$name' must be an integer."
            }

            if ($null -ne $minValue -and $parsed -lt [int]$minValue) {
                throw "Parameter '$name' must be >= $minValue."
            }
            if ($null -ne $maxValue -and $parsed -gt [int]$maxValue) {
                throw "Parameter '$name' must be <= $maxValue."
            }

            $value = $parsed
        }

        if ($type -eq "string" -and -not [string]::IsNullOrWhiteSpace([string]$control.Text) -and $pattern) {
            if ($control.Text -notmatch [string]$pattern) {
                throw "Parameter '$name' does not match required pattern."
            }
        }

        $values[$name] = $value
    }

    return $values
}
