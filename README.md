# steamhold

Block selected Steam games from **installing** or **running** on Windows.

Pick games from your local Steam library (interactive menu or one-liners). A small background task keeps the blocks in place.

> Self-control / focus tool. It is easy to undo if you have Administrator access. Use it on your own machine, on purpose.

## Features

- List installed Steam games from every library folder
- Block / unblock by AppID or name
- Interactive terminal menu
- Background watchdog (Scheduled Task)
- Locks the install folder path so Steam cannot recreate it
- Removes download residue (`appmanifest`, `downloading`, workshop leftovers)
- Stops matching game processes while blocked

## Requirements

- Windows 10/11
- PowerShell 5.1+ (built-in)
- Steam installed for the current user

## Quick start

```powershell
git clone https://github.com/umudik/steamhold.git
cd steamhold
powershell -ExecutionPolicy Bypass -File .\steamhold.ps1
```

Or without the menu:

```powershell
.\steamhold.ps1 list
.\steamhold.ps1 block 570
.\steamhold.ps1 install
.\steamhold.ps1 status
.\steamhold.ps1 unblock 570
.\steamhold.ps1 uninstall
```

Optional process names (when the exe name is not under the install folder path):

```powershell
.\steamhold.ps1 block 570 -ProcessName dota2
```

## How it works

1. You add games to `%LOCALAPPDATA%\steamhold\config.json`
2. `.\steamhold.ps1 install` registers a Scheduled Task named `steamhold`
3. Every few seconds the watchdog:
   - stops processes for blocked games
   - places a lock file where Steam expects the game folder
   - deletes install / download leftovers for those AppIDs

Uninstall removes the task and tries to clear lock files.

If a lock file was hardened with a Deny ACL, deleting it may need an elevated PowerShell:

```powershell
takeown /F "C:\Program Files (x86)\Steam\steamapps\common\<installdir>"
icacls "C:\Program Files (x86)\Steam\steamapps\common\<installdir>" /reset
del /f /q "C:\Program Files (x86)\Steam\steamapps\common\<installdir>"
```

## Commands

| Command | What it does |
|--------|----------------|
| `menu` (default) | Interactive picker |
| `list` | Show installed Steam games |
| `block <id\|name>` | Add a game to the block list |
| `unblock <id\|name>` | Remove a game and unlock paths |
| `status` | Show service + blocked games |
| `install` | Install / refresh the background task |
| `uninstall` | Remove the task and unlock everything |
| `sweep` | Run one enforcement pass now |

## Safety notes

- This is not a DRM bypass and not a Steam client mod. It only changes files under your own Steam libraries and runs a user Scheduled Task.
- Antivirus software may flag process-stopping + ACL changes. The source is small and readable — review it before running.
- Blocks apply to the Windows user who installed the service.

## Roadmap

- Optional “Buy Me a Coffee” support link
- Tray UI
- Block by AppID even when the game was never installed (manual installdir)

## License

MIT — see [LICENSE](LICENSE).
