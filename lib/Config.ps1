#requires -Version 5.1

function New-EmptySteamHoldConfig {
    [pscustomobject]@{
        version = 1
        blocked = @()
    }
}

function Read-SteamHoldConfig {
    Ensure-SteamHoldRoot | Out-Null
    $path = Get-SteamHoldConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        return New-EmptySteamHoldConfig
    }
    $raw = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
    if (-not $raw) {
        return New-EmptySteamHoldConfig
    }
    $parsed = $raw | ConvertFrom-Json
    if (-not $parsed.blocked) {
        $parsed | Add-Member -NotePropertyName blocked -NotePropertyValue @() -Force
    }
    if ($parsed.blocked -isnot [System.Array]) {
        $parsed.blocked = @($parsed.blocked)
    }
    return $parsed
}

function Save-SteamHoldConfig {
    param(
        [Parameter(Mandatory = $true)]
        $Config
    )
    Ensure-SteamHoldRoot | Out-Null
    $path = Get-SteamHoldConfigPath
    $json = $Config | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
}

function Get-BlockedGame {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId
    )
    $config = Read-SteamHoldConfig
    foreach ($entry in @($config.blocked)) {
        if ([string]$entry.appId -eq [string]$AppId) {
            return $entry
        }
    }
    return $null
}

function Add-BlockedGame {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$InstallDir,
        [string[]]$ProcessNames = @()
    )
    $config = Read-SteamHoldConfig
    $next = @()
    foreach ($entry in @($config.blocked)) {
        if ([string]$entry.appId -eq [string]$AppId) {
            continue
        }
        $next += $entry
    }
    $next += [pscustomobject]@{
        appId         = [string]$AppId
        name          = [string]$Name
        installDir    = [string]$InstallDir
        processNames  = @($ProcessNames | Where-Object { $_ })
        blockedAt     = (Get-Date).ToString('o')
    }
    $config.blocked = $next
    Save-SteamHoldConfig -Config $config
}

function Remove-BlockedGame {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId
    )
    $config = Read-SteamHoldConfig
    $next = @()
    foreach ($entry in @($config.blocked)) {
        if ([string]$entry.appId -eq [string]$AppId) {
            continue
        }
        $next += $entry
    }
    $config.blocked = $next
    Save-SteamHoldConfig -Config $config
}
