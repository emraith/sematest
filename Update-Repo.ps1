#requires -Version 7.4
<#
.SYNOPSIS
  Clone or fast-forward pull emraith/homelab using a GitHub App installation token.

.DESCRIPTION
  Reads the GitHub App private key (PEM), mints a short-lived installation access token via the
  GitHub REST API, then runs git clone or git fetch + pull --ff-only without storing the token in the remote URL.

.NOTES
  Default paths target server layout: C:\scripts_sync\, PEM under cert\, clone at homelab\.
  Optional repo-sync.config.json next to this script overrides defaults.
#>
[CmdletBinding()]
param(
    [string] $BasePath = 'C:\scripts_sync',
    [string] $Owner = 'emraith',
    [string] $Repo = 'homelab',
    [string] $AppId = '3551775',
    [string] $InstallationId = '128286341',
    [string] $PemPath,
    [string] $ClonePath,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-Base64Url {
    param([byte[]] $Bytes)
    [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-GitHubAppJwt {
    param(
        [string] $AppId,
        [string] $PemLiteralPath
    )
    if (-not (Test-Path -LiteralPath $PemLiteralPath)) {
        throw "Private key not found: $PemLiteralPath"
    }
    $pem = Get-Content -LiteralPath $PemLiteralPath -Raw
    $rsa = [System.Security.Cryptography.RSA]::Create()
    try {
        $rsa.ImportFromPem($pem)
    }
    catch {
        throw "Failed to read PEM at ${PemLiteralPath}: $_"
    }

    try {
        $iat = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 60
        $exp = $iat + 600
        $payloadObj = [ordered]@{
            iat = $iat
            exp = $exp
            iss = [int64] $AppId
        }
        $headerObj = @{ alg = 'RS256'; typ = 'JWT' }
        $headerJson = $headerObj | ConvertTo-Json -Compress
        $payloadJson = $payloadObj | ConvertTo-Json -Compress
        $headerB64 = ConvertTo-Base64Url ([System.Text.Encoding]::UTF8.GetBytes($headerJson))
        $payloadB64 = ConvertTo-Base64Url ([System.Text.Encoding]::UTF8.GetBytes($payloadJson))
        $unsigned = "$headerB64.$payloadB64"
        $sig = $rsa.SignData(
            [System.Text.Encoding]::UTF8.GetBytes($unsigned),
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
        $sigB64 = ConvertTo-Base64Url $sig
        return "$unsigned.$sigB64"
    }
    finally {
        $rsa.Dispose()
    }
}

function Get-GitHubInstallationToken {
    param(
        [string] $Jwt,
        [string] $InstallationId
    )
    $headers = @{
        Authorization            = "Bearer $Jwt"
        Accept                   = 'application/vnd.github+json'
        'X-GitHub-Api-Version'   = '2022-11-28'
    }
    $uri = "https://api.github.com/app/installations/$InstallationId/access_tokens"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers
    }
    catch {
        throw "GitHub installation token request failed: $_"
    }
    if (-not $response.token) {
        throw 'GitHub API did not return a token.'
    }
    return [string] $response.token
}

$scriptDir = $PSScriptRoot
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $scriptDir 'repo-sync.config.json'
}
if (Test-Path -LiteralPath $ConfigPath) {
    $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $apply = {
        param([string] $Name, [string] $VarName)
        $p = $cfg.PSObject.Properties[$Name]
        if ($p -and $null -ne $p.Value) {
            Set-Variable -Name $VarName -Value ([string] $p.Value) -Scope Script
        }
    }
    & $apply 'BasePath' 'BasePath'
    & $apply 'Owner' 'Owner'
    & $apply 'Repo' 'Repo'
    & $apply 'AppId' 'AppId'
    & $apply 'InstallationId' 'InstallationId'
    & $apply 'PemPath' 'PemPath'
    & $apply 'ClonePath' 'ClonePath'
}

if (-not $PemPath) {
    $PemPath = Join-Path $BasePath 'cert\myapp-githubsync.2026-05-04.private-key.pem'
}
if (-not $ClonePath) {
    $ClonePath = Join-Path $BasePath $Repo
}

$remoteHttps = "https://github.com/$Owner/$Repo.git"

Write-Host "Sync target: $remoteHttps"
Write-Host "Clone path:  $ClonePath"
Write-Host "PEM:         $PemPath"

$jwt = New-GitHubAppJwt -AppId $AppId -PemLiteralPath $PemPath
try {
    $token = Get-GitHubInstallationToken -Jwt $jwt -InstallationId $InstallationId
}
finally {
    Remove-Variable -Name jwt -ErrorAction SilentlyContinue
}

$pair = "x-access-token:$token"
$basic = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$extraHeader = "AUTHORIZATION: Basic $basic"
$gitExtra = "http.https://github.com/.extraheader=$extraHeader"

try {
    $gitDir = Join-Path $ClonePath '.git'
    if (-not (Test-Path -LiteralPath $gitDir)) {
        if (-not (Test-Path -LiteralPath $ClonePath)) {
            New-Item -ItemType Directory -Path $ClonePath -Force | Out-Null
        }
        & git @('-c', $gitExtra, 'clone', $remoteHttps, $ClonePath)
        if ($LASTEXITCODE -ne 0) { throw "git clone failed with exit code $LASTEXITCODE" }
    }
    else {
        & git @('-C', $ClonePath, '-c', $gitExtra, 'fetch', 'origin')
        if ($LASTEXITCODE -ne 0) { throw "git fetch failed with exit code $LASTEXITCODE" }
        & git @('-C', $ClonePath, '-c', $gitExtra, 'pull', '--ff-only')
        if ($LASTEXITCODE -ne 0) { throw "git pull --ff-only failed with exit code $LASTEXITCODE" }
    }
}
finally {
    Remove-Variable -Name token -ErrorAction SilentlyContinue
}

Write-Host 'Repository sync completed successfully.'
