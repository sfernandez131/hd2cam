"""Re-apply the mod before Helldivers starts.

Steam only rewrites game files on an update or a "Verify integrity" run, so
applying the mod right before every launch keeps it in place. Exits 0 when
the game is ready to start; the .bat launcher then starts it through Steam.
"""
import re
import sys

from bundle import STEAMAPPS
import build
import install

APP_ID = "394510"
MANIFEST = STEAMAPPS / f"appmanifest_{APP_ID}.acf"


def manifest_value(text, key):
    m = re.search(rf'"{key}"\s+"([^"]*)"', text)
    return m.group(1) if m else None


def steam_is_idle():
    """False while Steam has an update queued or in progress for the game."""
    text = MANIFEST.read_text(encoding="utf-8", errors="replace")
    fully_installed = manifest_value(text, "StateFlags") == "4"
    on_target_build = manifest_value(text, "buildid") == manifest_value(text, "TargetBuildID")
    return fully_installed and on_target_build


def main():
    if not steam_is_idle():
        print("Steam has an update pending for Helldivers. Let it finish in Steam,")
        print("then run this launcher again (patching now would be overwritten).")
        return 1
    src, out = install.MOD_SOURCE, install.MOD_BYTECODE
    if not out.exists() or src.stat().st_mtime > out.stat().st_mtime:
        build.build()
    install.install()
    return 0


if __name__ == "__main__":
    sys.exit(main())
