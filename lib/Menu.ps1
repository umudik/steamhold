#requires -Version 5.1

function Show-SteamHoldBanner {
    Write-Host ''
    Write-Host '  steamhold' -ForegroundColor Cyan
    Write-Host '  Block selected Steam games from installing or running.'
    Write-Host ''
}

function Show-SteamHoldStatus {
    $service = Get-SteamHoldServiceStatus
    $config = Read-SteamHoldConfig
    Write-Host "Service : $(if ($service.Installed) { $service.State } else { 'not installed' })"
    Write-Host "Config  : $(Get-SteamHoldConfigPath)"
    Write-Host "Blocked : $(@($config.blocked).Count)"
    foreach ($entry in @($config.blocked)) {
        Write-Host ("  - [{0}] {1}  ({2})" -f $entry.appId, $entry.name, $entry.installDir)
    }
    if (@($config.blocked).Count -lt 1) {
        Write-Host '  (none)'
    }
}

function Show-SteamHoldLibrary {
    $games = @(Get-SteamInstalledGames)
    if ($games.Count -lt 1) {
        Write-Host 'No installed Steam games found.'
        return @()
    }
    $i = 1
    foreach ($game in $games) {
        $mark = ''
        if (Get-BlockedGame -AppId $game.AppId) {
            $mark = ' [blocked]'
        }
        Write-Host ("  {0,3}. {1}  (AppID {2}){3}" -f $i, $game.Name, $game.AppId, $mark)
        $i++
    }
    return $games
}

function Invoke-BlockSelection {
    $games = Show-SteamHoldLibrary
    if ($games.Count -lt 1) {
        return
    }
    Write-Host ''
    $choice = Read-Host 'Number to block (or AppID / name)'
    if (-not $choice) {
        return
    }
    $game = $null
    if ($choice -match '^\d+$') {
        $asIndex = [int]$choice
        if ($asIndex -ge 1 -and $asIndex -le $games.Count) {
            $game = $games[$asIndex - 1]
        }
    }
    if (-not $game) {
        $found = Find-SteamGame -Query $choice
        if ($found -is [System.Array]) {
            Write-Host 'Multiple matches:'
            foreach ($item in $found) {
                Write-Host ("  {0} ({1})" -f $item.Name, $item.AppId)
            }
            return
        }
        $game = $found
    }
    if (-not $game) {
        Write-Host 'Game not found in local Steam library.'
        return
    }
    Add-BlockedGame -AppId $game.AppId -Name $game.Name -InstallDir $game.InstallDir
    Write-Host ("Blocked: {0} ({1})" -f $game.Name, $game.AppId)
    $service = Get-SteamHoldServiceStatus
    if (-not $service.Installed) {
        Write-Host 'Tip: run  steamhold.ps1 install  so the block stays active in the background.'
    } else {
        Invoke-SteamHoldSweep
    }
}

function Invoke-UnblockSelection {
    $config = Read-SteamHoldConfig
    $blocked = @($config.blocked)
    if ($blocked.Count -lt 1) {
        Write-Host 'Nothing is blocked.'
        return
    }
    $i = 1
    foreach ($entry in $blocked) {
        Write-Host ("  {0,3}. [{1}] {2}" -f $i, $entry.appId, $entry.name)
        $i++
    }
    Write-Host ''
    $choice = Read-Host 'Number to unblock (or AppID)'
    if (-not $choice) {
        return
    }
    $entry = $null
    if ($choice -match '^\d+$') {
        $asIndex = [int]$choice
        if ($asIndex -ge 1 -and $asIndex -le $blocked.Count) {
            $entry = $blocked[$asIndex - 1]
        }
    }
    if (-not $entry) {
        $entry = Get-BlockedGame -AppId $choice
    }
    if (-not $entry) {
        Write-Host 'Not on the block list.'
        return
    }
    $failed = Unlock-BlockedGamePaths -Entry $entry
    Remove-BlockedGame -AppId $entry.appId
    Write-Host ("Unblocked: {0}" -f $entry.name)
    if ($failed.Count -gt 0) {
        Write-Host 'Lock file still present (needs Administrator to delete):'
        foreach ($path in $failed) {
            Write-Host "  $path"
        }
    }
}

function Start-SteamHoldMenu {
    while ($true) {
        Show-SteamHoldBanner
        Show-SteamHoldStatus
        Write-Host ''
        Write-Host '  1) List Steam library'
        Write-Host '  2) Block a game'
        Write-Host '  3) Unblock a game'
        Write-Host '  4) Install background service'
        Write-Host '  5) Uninstall background service'
        Write-Host '  6) Run one sweep now'
        Write-Host '  0) Exit'
        Write-Host ''
        $pick = Read-Host 'Choose'
        switch ($pick) {
            '1' { Show-SteamHoldLibrary | Out-Null; Read-Host 'Enter to continue' | Out-Null }
            '2' { Invoke-BlockSelection; Read-Host 'Enter to continue' | Out-Null }
            '3' { Invoke-UnblockSelection; Read-Host 'Enter to continue' | Out-Null }
            '4' { Install-SteamHoldService; Read-Host 'Enter to continue' | Out-Null }
            '5' { Uninstall-SteamHoldService; Read-Host 'Enter to continue' | Out-Null }
            '6' { Invoke-SteamHoldSweep; Write-Host 'Sweep done.'; Read-Host 'Enter to continue' | Out-Null }
            '0' { return }
            default { }
        }
    }
}
