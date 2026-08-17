#requires -Version 5.1

function Get-SteamHoldGameRows {
    $blockedMap = @{}
    foreach ($entry in @(Read-SteamHoldConfig).blocked) {
        $blockedMap[[string]$entry.appId] = $entry
    }

    $rows = @()
    foreach ($game in @(Get-SteamInstalledGames)) {
        $blocked = $null
        if ($blockedMap.ContainsKey([string]$game.AppId)) {
            $blocked = $blockedMap[[string]$game.AppId]
        }
        $common = Join-Path $game.Library ("steamapps\common\" + $game.InstallDir)
        $rows += [pscustomobject]@{
            AppId      = [string]$game.AppId
            Name       = [string]$game.Name
            InstallDir = [string]$game.InstallDir
            Library    = [string]$game.Library
            Path       = [string]$common
            Blocked    = [bool]($null -ne $blocked)
            BlockedAt  = if ($blocked -and $blocked.blockedAt) { [string]$blocked.blockedAt } else { '' }
            Status     = if ($blocked) { 'Blocked' } else { 'Open' }
        }
    }

    foreach ($entry in @(Read-SteamHoldConfig).blocked) {
        $already = $false
        foreach ($row in $rows) {
            if ($row.AppId -eq [string]$entry.appId) {
                $already = $true
                break
            }
        }
        if ($already) {
            continue
        }
        $lib = ''
        foreach ($root in Get-SteamLibraryRoots) {
            $lib = $root
            break
        }
        $common = if ($lib) { Join-Path $lib ("steamapps\common\" + $entry.installDir) } else { $entry.installDir }
        $rows += [pscustomobject]@{
            AppId      = [string]$entry.appId
            Name       = [string]$entry.name
            InstallDir = [string]$entry.installDir
            Library    = [string]$lib
            Path       = [string]$common
            Blocked    = $true
            BlockedAt  = if ($entry.blockedAt) { [string]$entry.blockedAt } else { '' }
            Status     = 'Blocked'
        }
    }

    $rows | Sort-Object @{ Expression = 'Blocked'; Descending = $true }, Name
}

function Format-SteamHoldWhen {
    param([string]$Iso)
    if (-not $Iso) {
        return '—'
    }
    try {
        return ([datetime]$Iso).ToLocalTime().ToString('yyyy-MM-dd HH:mm')
    } catch {
        return $Iso
    }
}

function Start-SteamHoldUi {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        $args = @(
            '-NoProfile'
            '-ExecutionPolicy', 'Bypass'
            '-STA'
            '-File', (Join-Path (Split-Path -Parent $PSScriptRoot) 'steamhold.ps1')
            'ui'
        )
        Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Wait
        return
    }

    $state = @{
        Rows     = @()
        Selected = $null
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'steamhold'
    $form.Size = New-Object System.Drawing.Size(980, 620)
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = New-Object System.Drawing.Size(820, 480)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $form.BackColor = [System.Drawing.Color]::FromArgb(248, 248, 250)

    $header = New-Object System.Windows.Forms.Label
    $header.Text = 'steamhold'
    $header.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
    $header.Location = New-Object System.Drawing.Point(16, 12)
    $header.AutoSize = $true

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = 'Select a game with the arrow keys or mouse. Block and unblock from the right.'
    $subtitle.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 100)
    $subtitle.Location = New-Object System.Drawing.Point(18, 44)
    $subtitle.AutoSize = $true

    $serviceLabel = New-Object System.Windows.Forms.Label
    $serviceLabel.Location = New-Object System.Drawing.Point(18, 72)
    $serviceLabel.AutoSize = $true
    $serviceLabel.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 70)

    $search = New-Object System.Windows.Forms.TextBox
    $search.Location = New-Object System.Drawing.Point(16, 100)
    $search.Width = 420
    $search.Height = 28

    $filter = New-Object System.Windows.Forms.ComboBox
    $filter.DropDownStyle = 'DropDownList'
    $filter.Items.AddRange(@('All games', 'Blocked only', 'Open only'))
    $filter.SelectedIndex = 0
    $filter.Location = New-Object System.Drawing.Point(448, 100)
    $filter.Width = 150

    $list = New-Object System.Windows.Forms.ListView
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.HideSelection = $false
    $list.MultiSelect = $false
    $list.Location = New-Object System.Drawing.Point(16, 140)
    $list.Size = New-Object System.Drawing.Size(582, 380)
    $list.Anchor = 'Top,Bottom,Left'
    [void]$list.Columns.Add('Status', 90)
    [void]$list.Columns.Add('Game', 340)
    [void]$list.Columns.Add('AppID', 120)

    $detail = New-Object System.Windows.Forms.Panel
    $detail.Location = New-Object System.Drawing.Point(616, 100)
    $detail.Size = New-Object System.Drawing.Size(330, 420)
    $detail.Anchor = 'Top,Bottom,Right'
    $detail.BackColor = [System.Drawing.Color]::White
    $detail.BorderStyle = 'FixedSingle'

    $detailTitle = New-Object System.Windows.Forms.Label
    $detailTitle.Text = 'No game selected'
    $detailTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
    $detailTitle.Location = New-Object System.Drawing.Point(14, 14)
    $detailTitle.Size = New-Object System.Drawing.Size(300, 28)

    $detailBody = New-Object System.Windows.Forms.Label
    $detailBody.Location = New-Object System.Drawing.Point(14, 52)
    $detailBody.Size = New-Object System.Drawing.Size(300, 200)
    $detailBody.ForeColor = [System.Drawing.Color]::FromArgb(50, 50, 60)

    $btnBlock = New-Object System.Windows.Forms.Button
    $btnBlock.Text = 'Block'
    $btnBlock.Location = New-Object System.Drawing.Point(14, 270)
    $btnBlock.Size = New-Object System.Drawing.Size(140, 36)
    $btnBlock.Enabled = $false

    $btnUnblock = New-Object System.Windows.Forms.Button
    $btnUnblock.Text = 'Unblock'
    $btnUnblock.Location = New-Object System.Drawing.Point(168, 270)
    $btnUnblock.Size = New-Object System.Drawing.Size(140, 36)
    $btnUnblock.Enabled = $false

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = 'Refresh'
    $btnRefresh.Location = New-Object System.Drawing.Point(14, 318)
    $btnRefresh.Size = New-Object System.Drawing.Size(294, 32)

    $btnInstall = New-Object System.Windows.Forms.Button
    $btnInstall.Text = 'Install background service'
    $btnInstall.Location = New-Object System.Drawing.Point(14, 360)
    $btnInstall.Size = New-Object System.Drawing.Size(294, 32)

    $btnUninstall = New-Object System.Windows.Forms.Button
    $btnUninstall.Text = 'Uninstall service'
    $btnUninstall.Location = New-Object System.Drawing.Point(14, 398)
    $btnUninstall.Size = New-Object System.Drawing.Size(294, 32)

    $detail.Controls.AddRange(@(
            $detailTitle, $detailBody, $btnBlock, $btnUnblock, $btnRefresh, $btnInstall, $btnUninstall
        ))

    $statusBar = New-Object System.Windows.Forms.Label
    $statusBar.Location = New-Object System.Drawing.Point(16, 536)
    $statusBar.AutoSize = $true
    $statusBar.Anchor = 'Bottom,Left'
    $statusBar.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 100)

    function Update-ServiceLabel {
        $service = Get-SteamHoldServiceStatus
        if ($service.Installed) {
            $serviceLabel.Text = "Background service: $($service.State)"
            $serviceLabel.ForeColor = [System.Drawing.Color]::FromArgb(20, 120, 60)
        } else {
            $serviceLabel.Text = 'Background service: not installed (blocks only stick after Install)'
            $serviceLabel.ForeColor = [System.Drawing.Color]::FromArgb(150, 90, 20)
        }
    }

    function Show-SelectedDetail {
        $item = $list.SelectedItems
        if ($item.Count -lt 1) {
            $state.Selected = $null
            $detailTitle.Text = 'No game selected'
            $detailBody.Text = 'Use Up / Down to move through the list, then Block or Unblock.'
            $btnBlock.Enabled = $false
            $btnUnblock.Enabled = $false
            return
        }
        $row = $item[0].Tag
        $state.Selected = $row
        $detailTitle.Text = $row.Name
        $when = Format-SteamHoldWhen -Iso $row.BlockedAt
        $detailBody.Text = @(
            "Status:      $($row.Status)"
            "AppID:       $($row.AppId)"
            "Install dir: $($row.InstallDir)"
            "Library:     $($row.Library)"
            "Path:        $($row.Path)"
            "Blocked at:  $when"
        ) -join [Environment]::NewLine
        $btnBlock.Enabled = -not $row.Blocked
        $btnUnblock.Enabled = [bool]$row.Blocked
    }

    function Refresh-GameList {
        param([string]$KeepAppId = '')
        $query = $search.Text.Trim()
        $mode = $filter.SelectedItem
        $state.Rows = @(Get-SteamHoldGameRows)
        $list.BeginUpdate()
        $list.Items.Clear()
        foreach ($row in $state.Rows) {
            if ($mode -eq 'Blocked only' -and -not $row.Blocked) {
                continue
            }
            if ($mode -eq 'Open only' -and $row.Blocked) {
                continue
            }
            if ($query) {
                $hay = ($row.Name + ' ' + $row.AppId + ' ' + $row.InstallDir)
                if ($hay -notlike "*$query*") {
                    continue
                }
            }
            $item = New-Object System.Windows.Forms.ListViewItem($row.Status)
            [void]$item.SubItems.Add($row.Name)
            [void]$item.SubItems.Add($row.AppId)
            $item.Tag = $row
            if ($row.Blocked) {
                $item.ForeColor = [System.Drawing.Color]::FromArgb(160, 40, 40)
            }
            [void]$list.Items.Add($item)
        }
        $list.EndUpdate()
        Update-ServiceLabel
        $statusBar.Text = "$($list.Items.Count) shown · $($state.Rows.Count) total · config $(Get-SteamHoldConfigPath)"

        if ($KeepAppId) {
            foreach ($entry in $list.Items) {
                if ($entry.Tag.AppId -eq $KeepAppId) {
                    $entry.Selected = $true
                    $entry.EnsureVisible()
                    break
                }
            }
        } elseif ($list.Items.Count -gt 0 -and $list.SelectedItems.Count -lt 1) {
            $list.Items[0].Selected = $true
        }
        Show-SelectedDetail
    }

    $list.Add_SelectedIndexChanged({ Show-SelectedDetail })
    $search.Add_TextChanged({ Refresh-GameList })
    $filter.Add_SelectedIndexChanged({ Refresh-GameList })

    $btnRefresh.Add_Click({
            Refresh-GameList -KeepAppId $(if ($state.Selected) { $state.Selected.AppId } else { '' })
            $statusBar.Text = 'Refreshed.'
        })

    $btnBlock.Add_Click({
            if (-not $state.Selected) {
                return
            }
            $row = $state.Selected
            Add-BlockedGame -AppId $row.AppId -Name $row.Name -InstallDir $row.InstallDir
            if ((Get-SteamHoldServiceStatus).Installed) {
                Invoke-SteamHoldSweep
            }
            Refresh-GameList -KeepAppId $row.AppId
            $statusBar.Text = "Blocked $($row.Name)"
        })

    $btnUnblock.Add_Click({
            if (-not $state.Selected) {
                return
            }
            $row = $state.Selected
            $entry = Get-BlockedGame -AppId $row.AppId
            if (-not $entry) {
                return
            }
            $failed = Unlock-BlockedGamePaths -Entry $entry
            Remove-BlockedGame -AppId $row.AppId
            Refresh-GameList -KeepAppId $row.AppId
            if ($failed.Count -gt 0) {
                [System.Windows.Forms.MessageBox]::Show(
                    ("Unblocked, but this lock file still needs Administrator to delete:`n`n" + ($failed -join "`n")),
                    'steamhold',
                    'OK',
                    'Warning'
                ) | Out-Null
            }
            $statusBar.Text = "Unblocked $($row.Name)"
        })

    $btnInstall.Add_Click({
            try {
                Install-SteamHoldService
                Invoke-SteamHoldSweep
                Refresh-GameList -KeepAppId $(if ($state.Selected) { $state.Selected.AppId } else { '' })
                $statusBar.Text = 'Background service installed.'
            } catch {
                [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'steamhold', 'OK', 'Error') | Out-Null
            }
        })

    $btnUninstall.Add_Click({
            Uninstall-SteamHoldService
            Refresh-GameList -KeepAppId $(if ($state.Selected) { $state.Selected.AppId } else { '' })
            $statusBar.Text = 'Background service removed.'
        })

    $form.Controls.AddRange(@(
            $header, $subtitle, $serviceLabel, $search, $filter, $list, $detail, $statusBar
        ))

    $form.Add_Shown({
            Refresh-GameList
            $list.Focus()
        })

    [void]$form.ShowDialog()
}

function Start-SteamHoldMenu {
    Start-SteamHoldUi
}
