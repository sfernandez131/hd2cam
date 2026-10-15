"""Compile mod/hd2cam.lua to stripped LuaJIT 2.0 bytecode (mod/build/hd2cam.ljbc)."""
import subprocess
import sys
from pathlib import Path

from install import MOD_BYTECODE, MOD_SOURCE
from ljdis import parse

ROOT = Path(__file__).parent.parent
LUAJIT_SRC = ROOT / "third_party" / "LuaJIT-2.0" / "src"
LUAJIT = LUAJIT_SRC / "luajit.exe"


def build():
    MOD_BYTECODE.parent.mkdir(exist_ok=True)
    # luajit -b needs jit/*.lua on its package path; run from its src dir.
    r = subprocess.run([str(LUAJIT), "-b", "-s", str(MOD_SOURCE.resolve()), str(MOD_BYTECODE.resolve())],
                       cwd=LUAJIT_SRC, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"compile failed:\n{r.stderr}")
    code = MOD_BYTECODE.read_bytes()
    # Same header as the game's scripts: ESC 'L' 'J', version 1, flags = stripped.
    assert code[:5] == b"\x1bLJ\x01\x02", code[:5]
    parse(code)  # round-trips through our disassembler
    print(f"built {MOD_BYTECODE.name} ({len(code)} bytes)")


if __name__ == "__main__":
    build()
