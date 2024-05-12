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

$requestUrl = "$vrauri/iaas/api/network-profiles"
$result = Invoke-RestMethod -Method Get -Uri $requestUrl -Headers $header -SkipCertificateCheck
$AllNetworkProfiles = $result.content

$networkprofileList = @()
foreach($networkprofile in $AllNetworkProfiles)
{
    foreach($network in $networkprofile._links."fabric-networks".hrefs)
    {
        $networkprofileDetails = New-Object PSObject
        $networkprofileDetails | Add-Member -MemberType NoteProperty -Name "networkProfileId" -Value $networkprofile.id
        $networkprofileDetails | Add-Member -MemberType NoteProperty -Name "networkProfileName" -Value $networkprofile.name
    
        $requestUrl = "$vrauri$network"
        $result = Invoke-RestMethod -Method Get -Uri $requestUrl -Headers $header -SkipCertificateCheck
        $networkprofileDetails | Add-Member -MemberType NoteProperty -Name "cidr" -Value $result.cidr
        $networkprofileDetails | Add-Member -MemberType NoteProperty -Name "fabric-network-id" -Value $result.id
        if($result.tags -ne $null)
        {
            $tags = @()
            foreach($tag in $result.tags)
            {
                $tags += $tag
            }
            $networkprofileDetails | Add-Member -MemberType NoteProperty -Name "tags" -Value $tags
        }
        $networkprofileList += $networkprofileDetails
    }
}

$networkprofileList


