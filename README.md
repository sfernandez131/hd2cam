# HD2CAM

HELLDIVERS 2 style camera and controls for **HELLDIVERS (2015)**: over-the-shoulder camera with mouse / right-stick look, HD2 controller layout, aim zoom, a compass with map pings, longer view distance and a sky.

## Install

1. Install HELLDIVERS through Steam, launch it once and quit.
2. Download **[HD2CAM.zip](https://github.com/sfernandez131/hd2cam/releases/latest/download/HD2CAM.zip)** (latest release) and extract it anywhere, for example to `Downloads\HD2CAM`.
3. Open PowerShell in the extracted folder: in File Explorer, click the address bar, type `powershell` and press Enter.
4. Paste this line and press Enter, then choose **1 (Install)**:

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File .\HD2CAM.ps1
   ```

   `-ExecutionPolicy Bypass` lets Windows run this one script; it doesn't change any of your settings.
5. Start the game with the new **Helldivers (HD2CAM)** desktop shortcut. It re-applies the mod if Steam ever restores the game files, then starts the game through Steam.

**Update:** download the new zip, run the same command in its folder and choose 1.
**Uninstall:** run the same command and choose 2. It restores the original game file and removes the shortcut and the mod's folder.

The installer (`HD2CAM.ps1`) is plain text: [read it](nexus/HD2CAM.ps1) or open it in Notepad before running it.

## What the installer does

The game loads its scripts from bundle files. HD2CAM replaces one small script, `foundation/lua/build_date_information`, inside `contents\9cf71054ea26dddf`, with the mod (compiled LuaJIT 2.0 bytecode). The installer:

- finds HELLDIVERS through Steam's library list,
- backs up the original file to `<game>\HD2CAM\backup`,
- rewrites only that one script inside the file (every other resource is copied unchanged),
- copies itself and the mod to `<game>\HD2CAM` and makes the desktop shortcut.

No game files are distributed: everything is patched on the player's own copy.

## Source layout

| Path | What |
|---|---|
| `mod/hd2cam.lua` | The mod. Settings are at the top. |
| `nexus/HD2CAM.ps1` | The installer / launcher / uninstaller. |
| `nexus/README.txt` | README shipped in the release zip. |
| `hdtools/` | Python tools: bundle format (`bundle.py`), resource name hashing (`hashes.py`), LuaJIT 2.0 bytecode checker (`ljdis.py`), build and packaging. |

## Building

Requires Python 3 and LuaJIT **2.0** (the game embeds 2.0; 2.1 bytecode won't load). Build LuaJIT from the `v2.0` branch of https://luajit.org/git/luajit.git into `third_party/LuaJIT-2.0` (for example with MinGW: `mingw32-make` in `third_party/LuaJIT-2.0`).

```
python hdtools/build.py      # mod/hd2cam.lua -> mod/build/hd2cam.ljbc (stripped bytecode)
python hdtools/package.py    # release zip: dist/release/HD2CAM.zip
python hdtools/install.py install | uninstall | status   # development install on this PC
```

Bump `local VERSION` in `mod/hd2cam.lua` for each release.

## Notes

- Windows and the Steam version only.
- Co-op: every player gets their own camera. The mod is built to switch itself off in sessions where someone doesn't have it. Play with friends who have the mod, in private sessions.
- Bug reports: include `%APPDATA%\Arrowhead\Helldivers\hd2cam.log`.
- HELLDIVERS is a trademark of its owners. This is an unofficial fan mod and contains no game assets.
