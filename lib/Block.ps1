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

    $fresh = -not (Test-Path -LiteralPath $Path)
    if ($fresh) {
        Set-Content -LiteralPath $Path -Value 'steamhold: this path is locked on purpose.' -Encoding ASCII
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    try {
        $acl = Get-Acl -LiteralPath $Path
        $hasDeny = $acl.Access | Where-Object {
            $_.AccessControlType -eq 'Deny' -and $_.IdentityReference.Value -eq $me
        }
        if (-not $hasDeny) {
            (Get-Item -LiteralPath $Path -Force).Attributes = 'ReadOnly,Hidden,System'
            $acl.SetAccessRuleProtection($true, $false)
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($me, 'Read', 'Allow')))
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
                        $me, 'Write,Delete,ChangePermissions,TakeOwnership', 'Deny')))
            Set-Acl -LiteralPath $Path -AclObject $acl
            Write-SteamHoldLog "$(if ($fresh) { 'locked' } else { 're-locked' }): $Path"
        }
    } catch {
        Write-SteamHoldLog "lock acl skipped: $Path ($($_.Exception.Message))"
    }
}

function Unlock-SteamPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    try {
        (Get-Item -LiteralPath $Path -Force).Attributes = 'Normal'
    } catch { }

    try {
        $acl = Get-Acl -LiteralPath $Path
        $acl.SetAccessRuleProtection($false, $true)
        foreach ($rule in @($acl.Access)) {
            if ($rule.AccessControlType -eq 'Deny') {
                [void]$acl.RemoveAccessRule($rule)
            }
        }
        Set-Acl -LiteralPath $Path -AclObject $acl
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
