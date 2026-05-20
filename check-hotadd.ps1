function Get-VmConfigHotAdd {
    param(
        [Parameter(Mandatory = $true)]
        $Vm
    )

    $config = $Vm.ExtensionData.Config
    if ($null -ne $config) {
        return $config
    }

    $viewParams = if ($Vm.Id) {
        @{ Id = $Vm.Id }
    }
    else {
        @{ ViewType = 'VirtualMachine'; Filter = @{ Name = $Vm.Name } }
    }
    $view = Get-View @viewParams -ErrorAction Stop
    return $view.Config
}

if (-not (Get-Command -Name Get-VM -ErrorAction SilentlyContinue)) {
    throw 'PowerCLI is not available. Install or import VMware.VimAutomation.Core.'
}

$sessions = if ($Server) {
    @(Get-VIServer -Server $Server -ErrorAction Stop)
}
else {
    @(Get-VIServer -ErrorAction SilentlyContinue)
}

if ($sessions.Count -eq 0) {
    throw 'Not connected to vCenter. Run Connect-VIServer before calling this script.'
}

$getVmParams = @{
    Name       = $VmName
    ErrorAction = 'SilentlyContinue'
}
if ($Server) {
    $getVmParams.Server = $Server
}

$vm = Get-VM @getVmParams

if (-not $vm) {
    [PSCustomObject]@{
        VMName              = $VmName
        Found               = $false
        CpuHotAddEnabled    = $null
        MemoryHotAddEnabled = $null
    }
    return
}

$config = Get-VmConfigHotAdd -Vm $vm

[PSCustomObject]@{
    VMName              = $vm.Name
    Found               = $true
    CpuHotAddEnabled    = $config.CpuHotAddEnabled
    MemoryHotAddEnabled = $config.MemoryHotAddEnabled
}
