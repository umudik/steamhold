#requires -Version 5.1

function Get-VdfValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )
    $pattern = '"' + [regex]::Escape($Key) + '"\s+"([^"]*)"'
    $match = [regex]::Match($Text, $pattern)
    if ($match.Success) {
        return ($match.Groups[1].Value -replace '\\\\', '\')
    }
    return $null
}

function Get-SteamInstalledGames {
    $games = @()
    $seen = @{}
    foreach ($root in Get-SteamLibraryRoots) {
        $apps = Join-Path $root 'steamapps'
        if (-not (Test-Path -LiteralPath $apps)) {
            continue
        }
        Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                $text = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
                if (-not $text) {
                    return
                }
                $appId = Get-VdfValue -Text $text -Key 'appid'
                if (-not $appId) {
                    $fromName = [regex]::Match($_.Name, 'appmanifest_(\d+)\.acf')
                    if ($fromName.Success) {
                        $appId = $fromName.Groups[1].Value
                    }
                }
                if (-not $appId -or $seen.ContainsKey($appId)) {
                    return
                }
                $name = Get-VdfValue -Text $text -Key 'name'
                $installDir = Get-VdfValue -Text $text -Key 'installdir'
                if (-not $name) {
                    $name = "App $appId"
                }
                if (-not $installDir) {
                    $installDir = $name
                }
                $seen[$appId] = $true
                $games += [pscustomobject]@{
                    AppId      = [string]$appId
                    Name       = [string]$name
                    InstallDir = [string]$installDir
                    Library    = [string]$root
                    Manifest   = [string]$_.FullName
                }
            }
    }
    $games | Sort-Object Name
}

function Find-SteamGame {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query
    )
    $q = $Query.Trim()
    $games = Get-SteamInstalledGames
    foreach ($game in $games) {
        if ($game.AppId -eq $q) {
            return $game
        }
    }
    $exact = @($games | Where-Object { $_.Name -eq $q })
    if ($exact.Count -eq 1) {
        return $exact[0]
    }
    $fuzzy = @($games | Where-Object { $_.Name -like "*$q*" })
    if ($fuzzy.Count -eq 1) {
        return $fuzzy[0]
    }
    if ($fuzzy.Count -gt 1) {
        return $fuzzy
    }
    return $null
}
