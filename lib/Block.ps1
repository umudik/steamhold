#requires -Version 5.1

function Write-SteamHoldLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    Ensure-SteamHoldRoot | Out-Null
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $log = Get-SteamHoldLogPath
    Add-Content -LiteralPath $log -Value $line -ErrorAction SilentlyContinue
    if ((Test-Path -LiteralPath $log) -and ((Get-Item -LiteralPath $log).Length -gt 512KB)) {
        $keep = Get-Content -LiteralPath $log -Tail 500
        Set-Content -LiteralPath $log -Value $keep -Encoding UTF8
    }
}

function Lock-SteamPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Container) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        Write-SteamHoldLog "removed folder before lock: $Path"
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Set-Content -LiteralPath $Path -Value 'steamhold: this path is locked on purpose.' -Encoding ASCII
        Write-SteamHoldLog "locked: $Path"
    }

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try {
            (Get-Item -LiteralPath $Path -Force).Attributes = 'ReadOnly,Hidden'
        } catch { }
    }
}

function Unlock-SteamPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $true
    }

    try {
        (Get-Item -LiteralPath $Path -Force).Attributes = 'Normal'
    } catch { }

    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $changed = $false
        foreach ($rule in @($acl.Access)) {
            if ($rule.AccessControlType -eq 'Deny') {
                [void]$acl.RemoveAccessRule($rule)
                $changed = $true
            }
        }
        if ($changed) {
            $acl.SetAccessRuleProtection($false, $true)
            Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
        }
    } catch { }

    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        Write-SteamHoldLog "unlocked: $Path"
        return $true
    } catch {
        Write-SteamHoldLog "unlock failed: $Path ($($_.Exception.Message))"
        return $false
    }
}

function Start-SteamHoldElevatedUnlock {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Paths
    )
    $list = ($Paths | ForEach-Object { $_.Replace('"', '') }) -join '|'
    $script = @"
`$ErrorActionPreference = 'Continue'
`$paths = '$list'.Split('|') | Where-Object { `$_ }
foreach (`$path in `$paths) {
  if (-not (Test-Path -LiteralPath `$path)) { continue }
  takeown /F `$path | Out-Null
  icacls `$path /reset | Out-Null
  attrib -R -S -H `$path | Out-Null
  Remove-Item -LiteralPath `$path -Force -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath `$path) { cmd /c "del /f /q ``"`$path``"" | Out-Null }
}
"@
    $file = Join-Path $env:TEMP ('steamhold-elevated-unlock-' + [guid]::NewGuid().ToString('N') + '.ps1')
    Set-Content -LiteralPath $file -Value $script -Encoding UTF8
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $file
    ) -Wait | Out-Null
    Start-Sleep -Milliseconds 400
    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    $still = @()
    foreach ($path in $Paths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $still += $path
        }
    }
    return $still
}

function Stop-BlockedGameProcesses {
    param(
        [Parameter(Mandatory = $true)]
        $Entry
    )

    $names = @()
    if ($Entry.processNames) {
        $names = @($Entry.processNames | ForEach-Object { [string]$_ })
    }

    foreach ($proc in Get-CimInstance Win32_Process -ErrorAction SilentlyContinue) {
        $kill = $false
        $exe = [string]$proc.ExecutablePath
        $base = [IO.Path]::GetFileNameWithoutExtension([string]$proc.Name)

        foreach ($name in $names) {
            if ($base -and ($base -ieq $name)) {
                $kill = $true
            }
        }
        if ($Entry.installDir -and $exe -and ($exe -like "*\$($Entry.installDir)\*")) {
            $kill = $true
        }
        if ($kill) {
            try {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
                Write-SteamHoldLog "stopped $($proc.Name) pid $($proc.ProcessId) ($($Entry.name))"
            } catch { }
        }
    }
}

function Invoke-SteamHoldSweep {
    $config = Read-SteamHoldConfig
    foreach ($entry in @($config.blocked)) {
        if (-not $entry.appId -or -not $entry.installDir) {
            continue
        }
        Stop-BlockedGameProcesses -Entry $entry

        foreach ($root in Get-SteamLibraryRoots) {
            $apps = Join-Path $root 'steamapps'
            if (-not (Test-Path -LiteralPath $apps)) {
                continue
            }

            Lock-SteamPath (Join-Path $apps ("common\" + $entry.installDir))

            foreach ($junk in @(
                    (Join-Path $apps ("appmanifest_" + $entry.appId + ".acf")),
                    (Join-Path $apps ("downloading\" + $entry.appId)),
                    (Join-Path $apps ("temp\" + $entry.appId)),
                    (Join-Path $apps ("shadercache\" + $entry.appId)),
                    (Join-Path $apps ("workshop\appworkshop_" + $entry.appId + ".acf")),
                    (Join-Path $apps ("workshop\content\" + $entry.appId))
                )) {
                if (Test-Path -LiteralPath $junk) {
                    Remove-Item -LiteralPath $junk -Recurse -Force -ErrorAction SilentlyContinue
                    Write-SteamHoldLog "cleared install residue: $junk"
                }
            }
        }
    }
}

function Unlock-BlockedGamePaths {
    param(
        [Parameter(Mandatory = $true)]
        $Entry
    )
    $failed = @()
    foreach ($root in Get-SteamLibraryRoots) {
        $lock = Join-Path $root ("steamapps\common\" + $entry.installDir)
        if (Test-Path -LiteralPath $lock -PathType Leaf) {
            if (-not (Unlock-SteamPath -Path $lock)) {
                $failed += $lock
            }
        }
    }
    return $failed
}
