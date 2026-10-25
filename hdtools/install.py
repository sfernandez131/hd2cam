"""Install or uninstall the hd2cam mod.

usage: python install.py install | uninstall | status

Safe to run repeatedly. If Steam has replaced the bundle (game update or
"Verify integrity of game files"), the fresh vanilla copy becomes the new
backup before the mod is applied again.
"""
import shutil
import struct
import sys
from pathlib import Path

from bundle import (CONTENTS, GAME_DIR, build_bundle, bundle_paths, compress_bundle,
                    decompress_bundle, parse_bundle)
from hashes import murmur64, type_of

TARGET = murmur64("foundation/lua/build_date_information")
BACKUP_DIR = GAME_DIR / "hd2cam_backup"
BUNDLE_NAME_FILE = BACKUP_DIR / "target_bundle.txt"
DEFAULT_BUNDLE = "9cf71054ea26dddf"
MOD_DIR = Path(__file__).parent.parent / "mod"
MOD_BYTECODE = MOD_DIR / "build" / "hd2cam.ljbc"
MOD_SOURCE = MOD_DIR / "hd2cam.lua"


def find_target(entries):
    for e in entries:
        if e.name_hash == TARGET and type_of(e.type_hash) == "lua":
            return e
    return None


def target_bundle():
    """The bundle holding the loader script; rescans if an update moved it."""
    name = BUNDLE_NAME_FILE.read_text().strip() if BUNDLE_NAME_FILE.exists() else DEFAULT_BUNDLE
    path = CONTENTS / name
    if path.exists() and find_target(parse_bundle(decompress_bundle(path))[1]):
        return path
    print("loader script moved; scanning bundles...")
    for path in bundle_paths():
        if find_target(parse_bundle(decompress_bundle(path))[1]):
            BACKUP_DIR.mkdir(exist_ok=True)
            BUNDLE_NAME_FILE.write_text(path.name)
            return path
    raise SystemExit("could not find the loader script in any bundle")


def target_data(path):
    return find_target(parse_bundle(decompress_bundle(path))[1]).variants[0][1]


def is_vanilla(path):
    return target_data(path)[8:11] == b"\x1bLJ" and b"HD2CAM" not in target_data(path)


def mod_payload():
    """The mod as it should sit in the bundle, header included."""
    # Bytecode only: the game embeds LuaJIT 2.0 and crashes on plain source.
    if not MOD_BYTECODE.exists():
        raise SystemExit(f"{MOD_BYTECODE} is missing; run `python build.py` first")
    body = MOD_BYTECODE.read_bytes()
    return struct.pack("<II", len(body), 2) + body


def is_current(path):
    return target_data(path) == mod_payload()


def install():
    bundle = target_bundle()
    backup = BACKUP_DIR / bundle.name
    if is_current(bundle):
        print("mod already installed and up to date")
        return
    BACKUP_DIR.mkdir(exist_ok=True)
    if is_vanilla(bundle):
        shutil.copy2(bundle, backup)
        print(f"backed up vanilla bundle to {backup}")
    elif not backup.exists():
        raise SystemExit("bundle is modified and no backup exists; verify game files in Steam first")
    props, entries = parse_bundle(decompress_bundle(backup))
    find_target(entries).variants[0][1] = mod_payload()
    bundle.write_bytes(compress_bundle(build_bundle(props, entries)))
    print(f"installed mod into {bundle.name}")


def uninstall():
    bundle = target_bundle()
    backup = BACKUP_DIR / bundle.name
    if is_vanilla(bundle):
        print("already vanilla")
        return
    if not backup.exists():
        raise SystemExit("no backup found; use Steam > Verify integrity of game files")
    shutil.copy2(backup, bundle)
    print("restored original bundle")


def status():
    bundle = target_bundle()
    if is_vanilla(bundle):
        return "vanilla"
    if not MOD_BYTECODE.exists():
        return "modded (no local build to compare against)"
    return "modded (current)" if is_current(bundle) else "modded (outdated)"


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    {"install": install, "uninstall": uninstall}.get(cmd, lambda: None)()
    print("status:", status())
