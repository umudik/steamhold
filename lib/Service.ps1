#requires -Version 5.1

$script:SteamHoldTaskName = 'steamhold'

function Get-SteamHoldRepoWatchdogSource {
    Join-Path $PSScriptRoot '..\watchdog.ps1'
}

function Install-SteamHoldService {
    Ensure-SteamHoldRoot | Out-Null
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $source = Join-Path $projectRoot 'watchdog.ps1'
    if (-not (Test-Path -LiteralPath $source)) {
        throw "watchdog.ps1 not found next to the project files"
    }

    $root = Get-SteamHoldRoot
    $target = Get-SteamHoldWatchdogPath
    Copy-Item -LiteralPath $source -Destination $target -Force
    $libTarget = Join-Path $root 'lib'
    if (Test-Path -LiteralPath $libTarget) {
        Remove-Item -LiteralPath $libTarget -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'lib') -Destination $libTarget -Recurse -Force

    Unregister-ScheduledTask -TaskName $script:SteamHoldTaskName -Confirm:$false -ErrorAction SilentlyContinue

    $arg = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$target`""
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
    $logon = New-ScheduledTaskTrigger -AtLogOn
    $daily = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration ([TimeSpan]::MaxValue)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $script:SteamHoldTaskName -Action $action -Trigger @($logon, $daily) -Settings $settings -Principal $principal -Description 'steamhold: blocks selected Steam games from installing or running' -Force | Out-Null
    Start-ScheduledTask -TaskName $script:SteamHoldTaskName -ErrorAction SilentlyContinue
    Write-Host "Service installed. Task name: $script:SteamHoldTaskName"
    Write-Host "Config: $(Get-SteamHoldConfigPath)"
}

function Uninstall-SteamHoldService {
    Unregister-ScheduledTask -TaskName $script:SteamHoldTaskName -Confirm:$false -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*steamhold*watchdog.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    $config = Read-SteamHoldConfig
    $failed = @()
    foreach ($entry in @($config.blocked)) {
        $failed += Unlock-BlockedGamePaths -Entry $entry
    }

    if (Test-Path -LiteralPath (Get-SteamHoldWatchdogPath)) {
        Remove-Item -LiteralPath (Get-SteamHoldWatchdogPath) -Force -ErrorAction SilentlyContinue
    }

    Write-Host 'Service removed and locks cleared where possible.'
    if ($failed.Count -gt 0) {
        Write-Host 'Some lock files need an elevated unlock (Run PowerShell as Administrator):'
        foreach ($path in $failed) {
            Write-Host "  takeown /F `"$path`" && icacls `"$path`" /reset && del /f /q `"$path`""
        }
    }
}

function Get-SteamHoldServiceStatus {
    $task = Get-ScheduledTask -TaskName $script:SteamHoldTaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        return [pscustomobject]@{ Installed = $false; State = 'Missing' }
    }
    return [pscustomobject]@{ Installed = $true; State = [string]$task.State }
}
