#requires -Version 5.1
<#
.SYNOPSIS
  steamhold — block selected Steam games from installing or running.

.EXAMPLE
  .\steamhold.ps1
  .\steamhold.ps1 ui
  .\steamhold.ps1 list
  .\steamhold.ps1 block 570
  .\steamhold.ps1 unblock "Dota 2"
  .\steamhold.ps1 status
  .\steamhold.ps1 install
  .\steamhold.ps1 uninstall
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('ui', 'menu', 'list', 'block', 'unblock', 'status', 'install', 'uninstall', 'sweep')]
    [string]$Command = 'ui',

    [Parameter(Position = 1)]
    [string]$Target,

    [string[]]$ProcessName
)

$ErrorActionPreference = 'Stop'
$lib = Join-Path $PSScriptRoot 'lib'
. (Join-Path $lib 'Paths.ps1')
. (Join-Path $lib 'Config.ps1')
. (Join-Path $lib 'SteamLibrary.ps1')
. (Join-Path $lib 'Block.ps1')
. (Join-Path $lib 'Service.ps1')
. (Join-Path $lib 'Menu.ps1')
. (Join-Path $lib 'Ui.ps1')

switch ($Command) {
    { $_ -in @('ui', 'menu') } {
        Start-SteamHoldUi
    }
    'list' {
        Show-SteamHoldLibrary | Out-Null
    }
    'status' {
        Show-SteamHoldBanner
        Show-SteamHoldStatus
    }
    'install' {
        Install-SteamHoldService
    }
    'uninstall' {
        Uninstall-SteamHoldService
    }
    'sweep' {
        Invoke-SteamHoldSweep
        Write-Host 'Sweep done.'
    }
    'block' {
        if (-not $Target) {
            throw 'Usage: .\steamhold.ps1 block <AppID|name>'
        }
        $game = Find-SteamGame -Query $Target
        if ($game -is [System.Array]) {
            Write-Host 'Multiple matches — be more specific:'
            foreach ($item in $game) {
                Write-Host ("  {0} ({1})" -f $item.Name, $item.AppId)
            }
            exit 1
        }
        if (-not $game) {
            throw "Game not found in local Steam library: $Target"
        }
        $procs = @()
        if ($ProcessName) {
            $procs = $ProcessName
        }
        Add-BlockedGame -AppId $game.AppId -Name $game.Name -InstallDir $game.InstallDir -ProcessNames $procs
        Write-Host ("Blocked: {0} ({1})" -f $game.Name, $game.AppId)
        if ((Get-SteamHoldServiceStatus).Installed) {
            Invoke-SteamHoldSweep
        } else {
            Write-Host 'Install the service to keep the block active:  .\steamhold.ps1 install'
        }
    }
    'unblock' {
        if (-not $Target) {
            throw 'Usage: .\steamhold.ps1 unblock <AppID|name>'
        }
        $config = Read-SteamHoldConfig
        $entry = $null
        foreach ($item in @($config.blocked)) {
            if ([string]$item.appId -eq $Target -or [string]$item.name -eq $Target -or [string]$item.name -like "*$Target*") {
                $entry = $item
                break
            }
        }
        if (-not $entry) {
            throw "Not blocked: $Target"
        }
        $failed = Unlock-BlockedGamePaths -Entry $entry
        Remove-BlockedGame -AppId $entry.appId
        Write-Host ("Unblocked: {0}" -f $entry.name)
        if ($failed.Count -gt 0) {
            Write-Host 'Some locks need Administrator to delete:'
            $failed | ForEach-Object { Write-Host "  $_" }
        }
    }
}
