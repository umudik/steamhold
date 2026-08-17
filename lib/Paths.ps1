#requires -Version 5.1

function Get-SteamHoldRoot {
    Join-Path $env:LOCALAPPDATA 'steamhold'
}

function Get-SteamHoldConfigPath {
    Join-Path (Get-SteamHoldRoot) 'config.json'
}

function Get-SteamHoldLogPath {
    Join-Path (Get-SteamHoldRoot) 'steamhold.log'
}

function Get-SteamHoldWatchdogPath {
    Join-Path (Get-SteamHoldRoot) 'watchdog.ps1'
}

function Ensure-SteamHoldRoot {
    $root = Get-SteamHoldRoot
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    return $root
}

function Get-SteamInstallPath {
    try {
        $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
        if ($steam) {
            return ($steam -replace '/', '\')
        }
    } catch { }

    foreach ($fallback in @(
            "${env:ProgramFiles(x86)}\Steam",
            "$env:ProgramFiles\Steam"
        )) {
        if (Test-Path -LiteralPath $fallback) {
            return $fallback
        }
    }
    return $null
}

function Get-SteamLibraryRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $steam = Get-SteamInstallPath
    if (-not $steam) {
        return @()
    }
    $roots.Add($steam)

    $candidates = @(
        (Join-Path $steam 'steamapps\libraryfolders.vdf'),
        (Join-Path $steam 'config\libraryfolders.vdf')
    )
    foreach ($vdf in $candidates) {
        if (-not (Test-Path -LiteralPath $vdf)) {
            continue
        }
        $raw = Get-Content -LiteralPath $vdf -Raw -ErrorAction SilentlyContinue
        if (-not $raw) {
            continue
        }
        foreach ($match in [regex]::Matches($raw, '"path"\s+"([^"]+)"')) {
            $path = ($match.Groups[1].Value -replace '\\\\', '\')
            if ($path -and (Test-Path -LiteralPath $path)) {
                $roots.Add($path)
            }
        }
    }

    $roots | Where-Object { $_ } | Sort-Object -Unique
}
