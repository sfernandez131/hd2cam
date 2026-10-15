"""Build the release download.

usage: python package.py

The zip holds the compiled mod, the installer (HD2CAM.ps1) and the README;
no game files (the installer patches the player's own copy of the game).
Output: dist/release/HD2CAM.zip with a top-level HD2CAM-<version> folder.
The zip name stays the same across versions so the GitHub "latest release"
download link never changes.
"""
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

from build import LUAJIT, LUAJIT_SRC
from install import MOD_SOURCE
from ljdis import parse

ROOT = Path(__file__).parent.parent
KIT = ROOT / "nexus"
OUT = ROOT / "dist" / "release"
BUILD = ROOT / "mod" / "build"

# name: (zip and folder title, private build)
VARIANTS = {"standard": ("HD2CAM", False)}


def compile_variant(name, private):
    source = MOD_SOURCE.read_text(encoding="utf-8")
    src = BUILD / f"hd2cam_{name}.lua"
    out = src.with_suffix(".ljbc")
    BUILD.mkdir(exist_ok=True)
    src.write_text(source, encoding="utf-8", newline="\n")
    r = subprocess.run([str(LUAJIT), "-b", "-s", str(src.resolve()), str(out.resolve())],
                       cwd=LUAJIT_SRC, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"compile failed:\n{r.stderr}")
    code = out.read_bytes()
    assert code[:5] == b"\x1bLJ\x01\x02", code[:5]
    parse(code)
    return out


def version():
    m = re.search(r'^local VERSION = "([^"]+)"$', MOD_SOURCE.read_text(encoding="utf-8"), re.M)
    return m.group(1)


def readme(private):
    text = (KIT / "README.txt").read_text(encoding="utf-8")
    label = "Standard build"
    return text.replace("{version}", version()).replace("{build}", label)


def package():
    ver = version()
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (title, private) in VARIANTS.items():
        bytecode = compile_variant(name, private)
        folder = OUT / f"{title}-{ver}"
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir()
        shutil.copy2(bytecode, folder / "hd2cam.ljbc")
        script = (KIT / "HD2CAM.ps1").read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        (folder / "HD2CAM.ps1").write_bytes(script)
        (folder / "README.txt").write_bytes(readme(private).replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))
        archive = OUT / f"{title}.zip"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
            for f in sorted(folder.iterdir()):
                z.write(f, f"{folder.name}/{f.name}")
        print(f"{archive.name}: {', '.join(sorted(f.name for f in folder.iterdir()))} ({archive.stat().st_size} bytes)")


if __name__ == "__main__":
    package()
