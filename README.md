# steamhold

Block selected Steam games from **installing** or **running** on Windows.

Open the app, pick a game with the mouse or arrow keys, then hit **Block** / **Unblock**. The side panel shows status, path, and when it was blocked.

> Self-control / focus tool. Easy to undo with Administrator access. Use it on your own machine.

## Quick start

```powershell
git clone https://github.com/umudik/steamhold.git
cd steamhold
powershell -ExecutionPolicy Bypass -File .\steamhold.ps1
```

That opens the window. From there:

1. Select a game in the list (arrows or click)
2. Read status / path / blocked-at on the right
3. Press **Block** or **Unblock**
4. Press **Install background service** so blocks stay active

## Window

| Area | What you get |
|------|----------------|
| List | All Steam games, status column, search + filter |
| Detail | Name, AppID, install dir, library, path, blocked time |
| Actions | Block, Unblock, Refresh, Install / Uninstall service |

## Optional CLI

Still available if you want scripts:

```powershell
.\steamhold.ps1 list
.\steamhold.ps1 block 570
.\steamhold.ps1 status
.\steamhold.ps1 install
.\steamhold.ps1 unblock 570
.\steamhold.ps1 uninstall
```

## How it works

1. Blocked games are stored in `%LOCALAPPDATA%\steamhold\config.json`
2. **Install background service** registers a Scheduled Task named `steamhold`
3. The watchdog stops those games, locks their install folder path, and clears download leftovers

If a lock file still needs Administrator to delete:

```powershell
takeown /F "C:\Program Files (x86)\Steam\steamapps\common\<installdir>"
icacls "C:\Program Files (x86)\Steam\steamapps\common\<installdir>" /reset
del /f /q "C:\Program Files (x86)\Steam\steamapps\common\<installdir>"
```

## Requirements

- Windows 10/11
- PowerShell 5.1+
- Steam installed for the current user

## Safety notes

- Not a DRM bypass or Steam mod — only your libraries + a user Scheduled Task
- Antivirus may flag process-stop / ACL changes; the source is small — read it first
- Blocks apply to the Windows user who installed the service

## License

MIT — see [LICENSE](LICENSE).
