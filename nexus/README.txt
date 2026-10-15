HD2CAM {version} ({build}) - HELLDIVERS 2 style camera and controls for HELLDIVERS (2015)

Over-the-shoulder camera with mouse / right-stick look, HD2-style controller
layout, aim zoom, compass with map pings, longer view distance and a sky.

REQUIREMENTS
  HELLDIVERS (2015) on Steam, Windows.
  This download contains no game files: the installer patches your own copy.

RUNNING THE INSTALLER
  Open PowerShell in this folder: in File Explorer, click the address bar,
  type  powershell  and press Enter. Then paste this line and press Enter:

      powershell -NoProfile -ExecutionPolicy Bypass -File .\HD2CAM.ps1

  ("-ExecutionPolicy Bypass" lets Windows run this one script; it doesn't
  change any of your settings.)
  A small menu appears: 1 Install or update, 2 Uninstall, 3 Status.

INSTALL
  1. Install HELLDIVERS through Steam, launch it once, quit.
  2. Extract the zip anywhere (for example Downloads\HD2CAM).
  3. Run the installer (above) and choose 1.
  4. Start the game with the new "Helldivers (HD2CAM)" desktop shortcut.

  The shortcut re-applies the mod automatically if Steam restores the game
  files (after an update or "Verify integrity of game files"), then starts
  the game through Steam. Starting from Steam's Play button works too, as
  long as the mod is still applied.

  The installer keeps its files and a backup of the original game file in
  <Steam library>\steamapps\common\Helldivers\HD2CAM.

UPDATE OR SWITCH BUILD
  Run the new version's installer (or the other build's) and choose 1.
  It replaces whatever HD2CAM version is installed. Close the game first.

UNINSTALL
  Run the installer and choose 2, from this folder or from the copy the
  installer keeps in <Steam library>\steamapps\common\Helldivers\HD2CAM.
  It restores the original game file and removes the desktop shortcut and
  the HD2CAM folder (if you ran it from inside that folder, delete the
  folder yourself afterwards).
  Alternatively, Steam > right-click HELLDIVERS > Properties > Installed Files >
  Verify integrity of game files also removes the mod (then delete the
  shortcut and the HD2CAM folder yourself).

CONTROLS
  Mouse / right stick ........ look
  Right mouse / LT ........... aim (zooms in)
  C / R3 while aiming ........ swap shoulder
  Middle mouse / D-pad up .... ping the spot under the crosshair
  Controller (HD2 layout) .... RT fire, RB grenade, X reload, B dive,
                               R3 melee, LB + D-pad stratagems
  F8 ......................... mod on / off
  F9 ......................... sky style (engine / off / overlay)
  F7 ......................... view distance far / medium / vanilla
                               (starts medium on city and lava planets)

CO-OP
  Every player gets their own camera. The mod is built to switch itself
  fully off in any session where someone doesn't have it, so mixed lobbies
  play vanilla.
  Play with friends who have the mod, in private sessions.

TROUBLESHOOTING
  Log: %APPDATA%\Arrowhead\Helldivers\hd2cam.log (include it in bug reports).
  "already modified and no original backup": verify the game files in Steam
  (see UNINSTALL), then install again.
  "running scripts is disabled on this system": you ran HD2CAM.ps1 directly;
  use the full command under RUNNING THE INSTALLER instead.
  HD2CAM.ps1 is plain text: open it in Notepad to see exactly what it does.
  Source code: https://github.com/sfernandez131/hd2cam
