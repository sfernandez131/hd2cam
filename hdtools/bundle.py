"""Helldivers 1 (Bitsquid) bundle reading."""
import struct
import zlib
from pathlib import Path

def _steamapps():
    # Native Windows Python and MSYS/Cygwin Python spell C: differently.
    for root in (r"C:\Program Files (x86)\Steam", "/c/Program Files (x86)/Steam",
                 "/cygdrive/c/Program Files (x86)/Steam"):
        p = Path(root) / "steamapps"
        if p.is_dir():
            return p
    raise SystemExit("Steam install not found")


STEAMAPPS = _steamapps()
GAME_DIR = STEAMAPPS / "common" / "Helldivers"
CONTENTS = GAME_DIR / "contents"

CHUNK_SIZE = 0x10000
BUNDLE_VERSION = 0xF0000004


def decompress_bundle(path):
    """Return the raw (uncompressed) payload of a bundle file."""
    data = Path(path).read_bytes()
    version, total_size, _pad = struct.unpack_from("<III", data, 0)
    if version != BUNDLE_VERSION:
        raise ValueError(f"{path}: unexpected bundle version {version:#x}")
    out = bytearray()
    pos = 12
    while pos < len(data) and len(out) < total_size:
        (csize,) = struct.unpack_from("<I", data, pos)
        pos += 4
        chunk = data[pos:pos + csize]
        pos += csize
        out += chunk if csize == CHUNK_SIZE else zlib.decompress(chunk)
    return bytes(out[:total_size])


def compress_bundle(payload):
    """Inverse of decompress_bundle."""
    out = bytearray(struct.pack("<III", BUNDLE_VERSION, len(payload), 0))
    for i in range(0, len(payload), CHUNK_SIZE):
        block = payload[i:i + CHUNK_SIZE].ljust(CHUNK_SIZE, b"\0")
        z = zlib.compress(block, 9)
        if len(z) >= CHUNK_SIZE:
            out += struct.pack("<I", CHUNK_SIZE) + block
        else:
            out += struct.pack("<I", len(z)) + z
    return bytes(out)


class Entry:
    def __init__(self, type_hash, name_hash, unknown, variants):
        self.type_hash = type_hash
        self.name_hash = name_hash
        self.unknown = unknown
        self.variants = variants  # list of [lang, data, stream_size]


def parse_bundle(raw):
    """Split a decompressed bundle into (properties_block, entries)."""
    (count,) = struct.unpack_from("<I", raw, 0)
    props = raw[4:260]
    pos = 260 + count * 16  # skip the (type, name) index; headers repeat it
    entries = []
    for _ in range(count):
        t, n, nvar, unknown = struct.unpack_from("<QQII", raw, pos)
        pos += 24
        heads = []
        for _ in range(nvar):
            heads.append(struct.unpack_from("<III", raw, pos))
            pos += 12
        variants = []
        for lang, size, ssize in heads:
            variants.append([lang, raw[pos:pos + size], ssize])
            pos += size
        entries.append(Entry(t, n, unknown, variants))
    if pos != len(raw):
        raise ValueError(f"parse ended at {pos:#x}, payload is {len(raw):#x}")
    return props, entries


def build_bundle(props, entries):
    out = bytearray(struct.pack("<I", len(entries)) + props)
    for e in entries:
        out += struct.pack("<QQ", e.type_hash, e.name_hash)
    for e in entries:
        out += struct.pack("<QQII", e.type_hash, e.name_hash, len(e.variants), e.unknown)
        for lang, data, ssize in e.variants:
            out += struct.pack("<III", lang, len(data), ssize)
        for _, data, _ in e.variants:
            out += data
    return bytes(out)


def bundle_paths():
    return sorted(p for p in CONTENTS.iterdir() if p.is_file() and p.suffix == "" and len(p.name) == 16)
