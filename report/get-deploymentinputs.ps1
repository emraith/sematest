# bearer_token
$refreshtoken = ""

$vraFqdn=""
$vraUsername=""
$vraPassword=""
$vraDomain=""
$vrauri = "https://$vraFqdn"
$vraUrl="https://$vraFqdn/csp/gateway/am/api/login?access_token"

$vraBody="{""username"":""$vraUsername"",""password"":""$vraPassword"",""domain"":""$vraDomain""}"

$refreshtoken = Invoke-RestMethod -Method POST -ContentType "application/json" -URI $vraUrl -Body $vraBody


$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"

$header.Add("Content-Type", "application/json")

$bearer = Invoke-RestMethod -Method Post `
-Uri "$vrauri/iaas/api/login" `
-Headers $header `
-Body (@{'refreshToken'=$refreshtoken.refresh_token} | ConvertTo-Json)

$header.Add("Accept", "application/json")
$header.Add("Authorization", "Bearer " + $bearer.token)

$requestUrl = "$vrauri/deployment/api/deployments"
$deployments = Invoke-RestMethod -Method Get -Uri $requestUrl -Headers $header -SkipCertificateCheck
$deployments = $deployments.content



$list = @()
$topkey = "inputs"
$deployments = $deployments | select -skip 1
Write-Host "Deployments.inputs: $($deployments.inputs)"

$deployments.inputs | ForEach-Object {
    Write-Host "Current input: $_"
    $groupMembers = New-Object -TypeName PSObject
    $_.PSObject.Properties | ForEach-Object {
        $key = $_.Name
        $value = $_.Value
        Write-Host "Key: $key, Value: $value"
        $groupMembers | Add-Member -MemberType NoteProperty -Name "$($topkey).$key" -Value $value
    }
    $list += $groupMembers
}
$list
