action returning Array/Properties

$connectedNic = Get-VM $inputs[0].vmName | Get-NetworkAdapter | Select -First 1 | Select -ExpandProperty ConnectionState | Select -ExpandProperty Connected
    $output=@{connectedNic = $connectedNic}
    #$output = $connectedNic
    return $output


Workflow that reads output from action

System.log("actionResult_1[1] : " + JSON.stringify(actionResult_1[1]))

realnicConnected = actionResult_1[1].connectedNic
//System.log("actionResult_1[1].connectedNic : " + JSON.stringify(actionResult_1[1]).connectedNic)
System.log(realnicConnected)
if(realnicConnected == true){
    nicConnected = true
}
else
{
    nicConnected = false
}
