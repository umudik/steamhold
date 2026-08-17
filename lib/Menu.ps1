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
    foreach ($game in $games) {
        $mark = ''
        if (Get-BlockedGame -AppId $game.AppId) {
            $mark = ' [blocked]'
        }
        Write-Host ("  {0}  (AppID {1}){2}" -f $game.Name, $game.AppId, $mark)
    }
    return $games
}
