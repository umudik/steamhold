#requires -Version 5.1
$ErrorActionPreference = 'SilentlyContinue'

$mutex = New-Object System.Threading.Mutex($false, 'Global\steamhold-watchdog')
if (-not $mutex.WaitOne(0)) {
    exit 0
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$lib = Join-Path $here 'lib'
if (-not (Test-Path -LiteralPath (Join-Path $lib 'Paths.ps1'))) {
    $lib = Join-Path (Split-Path -Parent $here) 'lib'
}

. (Join-Path $lib 'Paths.ps1')
. (Join-Path $lib 'Config.ps1')
. (Join-Path $lib 'SteamLibrary.ps1')
. (Join-Path $lib 'Block.ps1')

Write-SteamHoldLog 'watchdog started'
while ($true) {
    try {
        Invoke-SteamHoldSweep
    } catch {
        Write-SteamHoldLog "error: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 5
}
