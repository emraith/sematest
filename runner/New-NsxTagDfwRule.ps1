#requires -Version 7.0

<#
.SYNOPSIS
    Creates or updates one NSX-T DFW rule from a tag name (intra-tag source/dest/scope).

.DESCRIPTION
    Builds rule naming and group paths from TagName, then PUTs to:
    {apiPrefix}{policyPath}/rules/{ruleId}

    Assumes the security policy and tag-based group already exist (rule-only flow).
    For VM tagging and group creation, see placeholder functions at the bottom of this file.

    ManagerType selects Local Manager (/policy/api/v1/infra) or Global Manager
    (/global-manager/api/v1/global-infra).

    Dot-source to load functions without running:
    . .\New-NsxTagDfwRule.ps1

.PARAMETER TagName
    Drives policy name (default), group id, and rule display name {TagName}_TO_{TagName}.

.PARAMETER WebSession
    Authenticated NSX WebRequestSession. If omitted, BaseUrl and Credential are required.

.PARAMETER BaseUrl
    NSX Manager base URL (required when WebSession is not supplied).

.PARAMETER Credential
    NSX API credentials (required when WebSession is not supplied).

.PARAMETER ManagerType
    Local or Global API prefix.

.PARAMETER DomainId
    Policy domain id (default: default).

.PARAMETER PolicyName
    Security policy display name; defaults to TagName.

.PARAMETER PolicyPath
    Path relative to apiPrefix, e.g. /domains/default/security-policies/my-policy.
    If omitted, derived from PolicyName and DomainId.

.PARAMETER Description
    Rule description, e.g. RITM#12345.

.PARAMETER RitmNumber
    Optional; if Description is omitted, formats Description as RITM#{RitmNumber}.

.PARAMETER ServiceNames
    Service aliases, port numbers, or full /infra/... paths. Default: MS_SQL_Services.

.PARAMETER Action
    Rule action (default ALLOW).

.PARAMETER Direction
    Rule direction (default IN_OUT).

.PARAMETER Logged
    Enable rule logging (default true).

.PARAMETER SkipCertificateCheck
    Skip TLS certificate validation.

.EXAMPLE
    $cred = Get-Credential
    .\New-NsxTagDfwRule.ps1 `
        -BaseUrl 'https://nsx-lm.corp.local' `
        -Credential $cred `
        -ManagerType Local `
        -TagName 'sql-mycluster-01' `
        -Description 'RITM#12345' `
        -ServiceNames 'MS_SQL_Services' `
        -SkipCertificateCheck

    Effective names for TagName sql-mycluster-01:
    - Policy display: sql-mycluster-01
    - Rule display: sql-mycluster-01_TO_sql-mycluster-01
    - Source/dest/scope: /infra/domains/default/groups/sql-mycluster-01

.NOTES
    Verification:
    1. Security policy exists at the derived PolicyPath for TagName.
    2. Group exists at /infra/domains/{DomainId}/groups/{derived-group-id}.
    3. MS_SQL_Services alias points to the correct object in your tenant (see $script:NsxServiceAliases).
    4. PUT returns 2xx; confirm rule in NSX UI (Security > Distributed Firewall).

    Reuse auth/helpers from nsx_group when available:
    . "$PSScriptRoot\..\nsx_group\New-NsxLocalManagerSecurityGroup.ps1"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TagName,

    [Parameter(Mandatory = $false)]
    [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,

    [Parameter(Mandatory = $false)]
    [string]$BaseUrl,

    [Parameter(Mandatory = $false)]
    [pscredential]$Credential,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Local', 'Global')]
    [string]$ManagerType = 'Local',

    [Parameter(Mandatory = $false)]
    [string]$DomainId = 'default',

    [Parameter(Mandatory = $false)]
    [string]$PolicyName,

    [Parameter(Mandatory = $false)]
    [string]$PolicyPath,

    [Parameter(Mandatory = $false)]
    [string]$Description,

    [Parameter(Mandatory = $false)]
    [string]$RitmNumber,

    [Parameter(Mandatory = $false)]
    [string[]]$ServiceNames = @('MS_SQL_Services'),

    [Parameter(Mandatory = $false)]
    [ValidateSet('ALLOW', 'DROP', 'REJECT', 'JUMP_TO_APPLICATION')]
    [string]$Action = 'ALLOW',

    [Parameter(Mandatory = $false)]
    [ValidateSet('IN', 'OUT', 'IN_OUT')]
    [string]$Direction = 'IN_OUT',

    [Parameter(Mandatory = $false)]
    [bool]$Logged = $true,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCertificateCheck
)

# Known service aliases — adjust MS_SQL_Services path for your NSX tenant if needed.
$script:NsxServiceAliases = @{
    'MS_SQL_Services' = '/infra/domains/default/groups/MS_SQL_Services'
}

$nsxGroupHelperScript = Join-Path $PSScriptRoot '..\nsx_group\New-NsxLocalManagerSecurityGroup.ps1'
if (Test-Path -LiteralPath $nsxGroupHelperScript) {
    . $nsxGroupHelperScript
} else {
    function Normalize-NsxBaseUrl {
        param([Parameter(Mandatory = $true)][string]$Url)
        $u = $Url.Trim().TrimEnd('/')
        if ($u -notmatch '^https?://') {
            $u = "https://$u"
        }
        return $u
    }

    function Get-DerivedGroupPolicyId {
        param([Parameter(Mandatory = $true)][string]$Name)
        $id = $Name.Trim().ToLowerInvariant() -replace '\s+', '-' -replace '[^a-z0-9_.-]', ''
        if ([string]::IsNullOrWhiteSpace($id)) {
            throw "Cannot derive policy id from name '$Name'."
        }
        return $id
    }

    function Connect-NsxSession {
        param(
            [Parameter(Mandatory = $true)][string]$BaseUrl,
            [Parameter(Mandatory = $true)][pscredential]$Credential,
            [switch]$SkipCertificateCheck
        )

        $plainPassword = $Credential.GetNetworkCredential().Password
        $authUrl = "$BaseUrl/api/session/create"
        $authPayload = @{
            username = $Credential.UserName
            password = $plainPassword
        } | ConvertTo-Json

        $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $null = Invoke-RestMethod -Uri $authUrl `
            -Method Post `
            -Body $authPayload `
            -ContentType 'application/json' `
            -WebSession $session `
            -SkipCertificateCheck:$SkipCertificateCheck

        if ($session.Cookies.Count -eq 0) {
            throw 'Authentication failed: no session cookies returned from NSX.'
        }
        return $session
    }

    function Resolve-NsxRestFailure {
        param([Parameter(Mandatory = $true)]$ErrorRecord)

        $detail = [System.Collections.Generic.List[string]]::new()
        [void]$detail.Add($ErrorRecord.Exception.Message)

        if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
            [void]$detail.Add($ErrorRecord.ErrorDetails.Message.TrimEnd())
        }

        $resp = $ErrorRecord.Exception.Response
        if ($resp -is [System.Net.Http.HttpResponseMessage] -and $resp.Content) {
            try {
                $task = $resp.Content.ReadAsStringAsync()
                $task.Wait()
                $body = $task.Result
                if (-not [string]::IsNullOrWhiteSpace($body)) {
                    [void]$detail.Add($body.TrimEnd())
                }
            } catch {
                # ignore secondary read failures
            }
        }

        return ($detail -join "`n")
    }
}

function Get-NsxApiPrefix {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Local', 'Global')]
        [string]$ManagerType
    )

    switch ($ManagerType) {
        'Global' { return '/global-manager/api/v1/global-infra' }
        default  { return '/policy/api/v1/infra' }
    }
}

function Get-NsxGroupPath {
    param(
        [Parameter(Mandatory = $true)][string]$DomainId,
        [Parameter(Mandatory = $true)][string]$GroupId
    )

    return "/infra/domains/$DomainId/groups/$GroupId"
}

function Resolve-NsxPolicyPath {
    param(
        [Parameter(Mandatory = $true)][string]$DomainId,
        [Parameter(Mandatory = $true)][string]$PolicyName,
        [Parameter(Mandatory = $false)][string]$PolicyPath
    )

    if (-not [string]::IsNullOrWhiteSpace($PolicyPath)) {
        $path = $PolicyPath.Trim()
        if ($path -notmatch '^/') {
            $path = "/$path"
        }
        return $path
    }

    $policyId = Get-DerivedGroupPolicyId -Name $PolicyName
    return "/domains/$DomainId/security-policies/$policyId"
}

function Resolve-NsxServicePaths {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ServiceNames,

        [Parameter(Mandatory = $true)]
        [string]$DomainId
    )

    $paths = [System.Collections.Generic.List[string]]::new()

    foreach ($raw in $ServiceNames) {
        if ([string]::IsNullOrWhiteSpace($raw)) {
            continue
        }

        foreach ($item in ($raw -split ',')) {
            $name = $item.Trim()
            if ($name -eq '') {
                continue
            }

            if ($name -match '^/infra/') {
                [void]$paths.Add($name)
            } elseif ($name -eq 'ICMP' -or $name -eq 'icmp') {
                [void]$paths.Add('/infra/services/ICMP-ALL')
            } elseif ($name -match '^\d+$') {
                [void]$paths.Add("/infra/domains/$DomainId/services/TCP$name")
            } elseif ($script:NsxServiceAliases.ContainsKey($name)) {
                [void]$paths.Add($script:NsxServiceAliases[$name])
            } else {
                throw "Unknown service alias '$name'. Add it to `$script:NsxServiceAliases or pass a full /infra/... path."
            }
        }
    }

    if ($paths.Count -eq 0) {
        throw 'At least one service must be specified in ServiceNames.'
    }

    return @($paths)
}

function New-NsxTagDfwRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,
        [Parameter(Mandatory = $true)][string]$ApiPrefix,
        [Parameter(Mandatory = $true)][string]$PolicyPath,
        [Parameter(Mandatory = $true)][string]$TagName,
        [Parameter(Mandatory = $true)][string]$DomainId,
        [Parameter(Mandatory = $false)][string]$Description,
        [Parameter(Mandatory = $true)][string[]]$ServiceNames,
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][string]$Direction,
        [Parameter(Mandatory = $true)][bool]$Logged,
        [switch]$SkipCertificateCheck
    )

    $ruleDisplayName = "${TagName}_TO_${TagName}"
    $ruleId = Get-DerivedGroupPolicyId -Name $ruleDisplayName
    $groupId = Get-DerivedGroupPolicyId -Name $TagName
    $groupPath = Get-NsxGroupPath -DomainId $DomainId -GroupId $groupId
    $servicePaths = Resolve-NsxServicePaths -ServiceNames $ServiceNames -DomainId $DomainId

    $normalizedPolicyPath = $PolicyPath.Trim()
    if ($normalizedPolicyPath -notmatch '^/') {
        $normalizedPolicyPath = "/$normalizedPolicyPath"
    }

    $encodedRuleId = [uri]::EscapeDataString($ruleId)
    $putUrl = "$BaseUrl$ApiPrefix$normalizedPolicyPath/rules/$encodedRuleId"
    $rulePath = "$normalizedPolicyPath/rules/$ruleId"

    $ruleBody = [ordered]@{
        resource_type      = 'Rule'
        display_name       = $ruleDisplayName
        action             = $Action.ToUpperInvariant()
        direction          = $Direction.ToUpperInvariant()
        disabled           = $false
        logged             = $Logged
        source_groups      = @($groupPath)
        destination_groups = @($groupPath)
        scope              = @($groupPath)
        services           = @($servicePaths)
    }

    if (-not [string]::IsNullOrWhiteSpace($Description)) {
        $ruleBody['description'] = $Description
    }

    $json = $ruleBody | ConvertTo-Json -Depth 10

    Write-Verbose "PUT $putUrl"
    Write-Verbose "Rule payload: $json"

    try {
        $null = Invoke-RestMethod -Uri $putUrl `
            -Method Put `
            -Body $json `
            -ContentType 'application/json' `
            -WebSession $WebSession `
            -SkipCertificateCheck:$SkipCertificateCheck `
            -ErrorAction Stop
    } catch {
        $full = Resolve-NsxRestFailure -ErrorRecord $_
        Write-Error -Message $full -ErrorAction Stop
    }

    return [pscustomobject]@{
        Success    = $true
        RuleName   = $ruleDisplayName
        RuleId     = $ruleId
        RulePath   = $rulePath
        PolicyPath = $normalizedPolicyPath
        GroupPath  = $groupPath
        PutUrl     = $putUrl
    }
}

# --- Placeholders for future integration (not used in rule-only flow) ---

function New-NsxTagBasedSecurityGroup {
    <#
    .SYNOPSIS
        Placeholder for tag-based policy group creation.
    .NOTES
        Implement or wire to: c:\code\vRO\nsx-firewall\actions\createNsxTagBasedGroup.js
        Or extend: c:\code\nsx_group\New-NsxLocalManagerSecurityGroup.ps1
    #>
    [CmdletBinding()]
    param()

    throw 'NotImplemented: New-NsxTagBasedSecurityGroup. See createNsxTagBasedGroup.js or nsx_group scripts.'
}

function Add-NsxVmTag {
    <#
    .SYNOPSIS
        Placeholder for applying an NSX tag to a VM.
    .NOTES
        Implement or wire to: c:\code\vRO\nsx-firewall\actions\addNsxTagToVm.js
    #>
    [CmdletBinding()]
    param()

    throw 'NotImplemented: Add-NsxVmTag. See addNsxTagToVm.js.'
}

function Ensure-NsxSecurityPolicy {
    <#
    .SYNOPSIS
        Placeholder to ensure a security policy exists before adding rules.
    .NOTES
        Rule-only flow assumes the policy named TagName already exists at PolicyPath.
    #>
    [CmdletBinding()]
    param()

    throw 'NotImplemented: Ensure-NsxSecurityPolicy. Create the policy in NSX or implement this hook.'
}

if ($MyInvocation.InvocationName -eq '.') {
    return
}

if ([string]::IsNullOrWhiteSpace($TagName)) {
    throw 'TagName is required when running this script.'
}

if (-not $PolicyName) {
    $PolicyName = $TagName
}

if ([string]::IsNullOrWhiteSpace($Description) -and -not [string]::IsNullOrWhiteSpace($RitmNumber)) {
    $Description = "RITM#$RitmNumber"
}

if (-not $WebSession) {
    if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
        throw 'BaseUrl is required when WebSession is not provided.'
    }
    if (-not $Credential) {
        throw 'Credential is required when WebSession is not provided.'
    }
}

$baseUrl = Normalize-NsxBaseUrl -Url $BaseUrl
if (-not $WebSession) {
    $WebSession = Connect-NsxSession -BaseUrl $baseUrl -Credential $Credential -SkipCertificateCheck:$SkipCertificateCheck
}

$apiPrefix = Get-NsxApiPrefix -ManagerType $ManagerType
$resolvedPolicyPath = Resolve-NsxPolicyPath -DomainId $DomainId -PolicyName $PolicyName -PolicyPath $PolicyPath

Write-Host "Creating DFW rule for tag: $TagName"
Write-Host "  Policy path: $resolvedPolicyPath"
Write-Host "  Rule name:   ${TagName}_TO_${TagName}"
Write-Host "  Manager:     $ManagerType"

$result = New-NsxTagDfwRule `
    -BaseUrl $baseUrl `
    -WebSession $WebSession `
    -ApiPrefix $apiPrefix `
    -PolicyPath $resolvedPolicyPath `
    -TagName $TagName `
    -DomainId $DomainId `
    -Description $Description `
    -ServiceNames $ServiceNames `
    -Action $Action `
    -Direction $Direction `
    -Logged $Logged `
    -SkipCertificateCheck:$SkipCertificateCheck

Write-Host "Rule created/updated: $($result.RuleName) ($($result.RulePath))"
$result
