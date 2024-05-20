# Connect to your vCenter server
Connect-VIServer -Server <vCenterServer> -User <Username> -Password <Password>

# Get all VMs in the cluster
$cluster = Get-Cluster -Name <ClusterName>
$vms = Get-VM -Location $cluster

# Loop through each VM
foreach ($vm in $vms) {
    # Get the operating system of the VM
    $os = $vm.ExtensionData.Guest.GuestFullName

    # Check if the operating system is Suse Linux, Red Hat Linux, or Windows
    if ($os -like "*SUSE Linux*" -or $os -like "*Red Hat Enterprise Linux*" -or $os -like "*Windows*") {
        # Apply the correct tag for the operating system
        if ($os -like "*SUSE Linux*") {
            $tag = "Suse Linux"
        }
        elseif ($os -like "*Red Hat Enterprise Linux*") {
            $tag = "Red Hat Linux"
        }
        elseif ($os -like "*Windows*") {
            $tag = "Windows"
        }

        # Apply the tag to the VM
        New-TagAssignment -Tag $tag -Entity $vm
    }
}

# Disconnect from the vCenter server
Disconnect-VIServer -Server <vCenterServer> -Confirm:$false
