<#
.SYNOPSIS
    Exports NSX-T fabric virtual machines and their tags to a CSV file.

.DESCRIPTION
    Connects to an NSX-T manager via REST API, retrieves all virtual machines
    (with display_name, external_id, tags) using cursor-based pagination,
    and exports one row per VM to CSV. Tags are concatenated into a single
    column separated by semicolon (;). Each tag is formatted as scope:tag when
    scope is non-empty (including whitespace-only scopes such as a single space,
    written literally as scope:tag). Null or empty-string scope uses :tag only.

.PARAMETER NsxtManager
    FQDN or IP address of the NSX-T manager.

.PARAMETER Credential
    PSCredential for API Basic Auth (username/password). If not provided, will prompt.

.PARAMETER OutputPath
    Full or relative path for the output CSV file.

.PARAMETER SkipCertificateCheck
    Skip TLS certificate validation. Use only for lab or self-signed certificates;
    not recommended for production.

.EXAMPLE
    .\Export-NsxtVmTagsToCsv.ps1 -NsxtManager 'nsxt.company.com' -OutputPath '.\vm-tags.csv' -Credential (Get-Credential)

.EXAMPLE
    .\Export-NsxtVmTagsToCsv.ps1 -NsxtManager '192.168.1.10' -OutputPath '.\vm-tags.csv' -SkipCertificateCheck
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]
    $NsxtManager,

    [Parameter(Mandatory = $false)]
    [PSCredential]
    $Credential,

    [Parameter(Mandatory = $true)]
    [string]
    $OutputPath,

    [switch]
    $SkipCertificateCheck
)

# Ensure we have credentials
if (-not $Credential) {
    $Credential = Get-Credential -Message 'NSX-T Manager (Basic Auth)'
}

# Normalize manager host (no scheme)
$hostOnly = $NsxtManager -replace '^https?://', '' -replace '/$', ''
$baseUri = "https://$hostOnly/api/v1/fabric/virtual-machines"

Write-Host "Connecting to NSX-T manager at $hostOnly..."

# Pagination: collect all VM results
$allVms = [System.Collections.Generic.List[object]]::new()
$queryParams = @{
    included_fields = 'display_name,external_id,tags'
    page_size       = 1000
}
$cursor = $null

do {
    $uri = $baseUri
    $query = ($queryParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$([Uri]::EscapeDataString($_.Value))" }) -join '&'
    if ($cursor) {
        $query = $query + '&cursor=' + [Uri]::EscapeDataString($cursor)
    }
    if ($query) {
        $uri = "$baseUri`?$query"
    }

    try {
        $irmParams = @{
            Uri             = $uri
            Method          = 'Get'
            Authentication  = 'Basic'
            Credential      = $Credential
            ContentType     = 'application/json'
            ErrorAction     = 'Stop'
        }
        # -SkipCertificateCheck is supported in PowerShell 6+ (Core) only
        if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
            $irmParams['SkipCertificateCheck'] = $true
        }
        elseif ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -lt 6) {
            Write-Warning '-SkipCertificateCheck is ignored on Windows PowerShell 5.1. Use PowerShell 6+ or trust the manager certificate.'
        }
        $response = Invoke-RestMethod @irmParams
    }
    catch {
        Write-Error "NSX-T API request failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $reader.BaseStream.Position = 0
            $body = $reader.ReadToEnd()
            if ($body) { Write-Error "Response: $body" }
        }
        exit 1
    }

    $pageResults = @($response.results)
    if ($pageResults.Count -gt 0) {
        foreach ($vm in $pageResults) {
            $allVms.Add($vm)
        }
        Write-Verbose "Fetched $($pageResults.Count) VMs (total so far: $($allVms.Count))."
    }

    $cursor = $response.cursor
} while ($cursor)

Write-Host "Processing $($allVms.Count) VM(s) for export..."

# Scopes to exclude from export (tag is skipped; VM still included, with empty Tags if none remain)
$excludedScopes = @('data.protection.requirements', 'licensed.os')

# Build CSV rows: one per VM, Tags = semicolon-joined "scope:tag" or ":tag" (null/empty scope only)
$rows = foreach ($vm in $allVms) {
    $tagParts = @()
    $vmTags = @($vm.tags)
    if ($vmTags.Count -gt 0) {
        foreach ($t in $vmTags) {
            $scope = $t.scope
            if ($excludedScopes -contains $scope) { continue }
            $tag  = $t.tag
            if ([string]::IsNullOrEmpty($scope)) {
                $tagParts += ":$tag"
            }
            else {
                $tagParts += "${scope}:${tag}"
            }
        }
    }
    $tagsString = $tagParts -join ';'

    [PSCustomObject]@{
        DisplayName = $vm.display_name
        ExternalId  = $vm.external_id
        Tags        = $tagsString
    }
}

# Export to CSV
$rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "Export complete: $($rows.Count) virtual machine(s) written to '$OutputPath'."
