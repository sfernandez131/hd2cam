"""Disassembler for stripped LuaJIT 2.0 bytecode dumps (version 1)."""
import struct
import sys
from pathlib import Path

OPS = """ISLT ISGE ISLE ISGT ISEQV ISNEV ISEQS ISNES ISEQN ISNEN ISEQP ISNEP
ISTC ISFC IST ISF MOV NOT UNM LEN ADDVN SUBVN MULVN DIVVN MODVN ADDNV SUBNV
MULNV DIVNV MODNV ADDVV SUBVV MULVV DIVVV MODVV POW CAT KSTR KCDATA KSHORT
KNUM KPRI KNIL UGET USETV USETS USETN USETP UCLO FNEW TNEW TDUP GGET GSET
TGETV TGETS TGETB TSETV TSETS TSETB TSETM CALLM CALL CALLMT CALLT ITERC ITERN
VARG ISNEXT RETM RET RET0 RET1 FORI JFORI FORL IFORL JFORL ITERL IITERL JITERL
LOOP ILOOP JLOOP JMP FUNCF IFUNCF JFUNCF FUNCV IFUNCV JFUNCV FUNCC FUNCCW""".split()

# (A, B, C/D) operand kinds; B is None for AD-format instructions.
V, S, N, P, L, SL, J, U, F, T = "var str num pri lit slit jump uv func tab".split()
MODES = {}
for o in "ISLT ISGE ISLE ISGT ISEQV ISNEV".split(): MODES[o] = (V, None, V)
MODES.update(ISEQS=(V, None, S), ISNES=(V, None, S), ISEQN=(V, None, N), ISNEN=(V, None, N),
             ISEQP=(V, None, P), ISNEP=(V, None, P), ISTC=(V, None, V), ISFC=(V, None, V),
             IST=(None, None, V), ISF=(None, None, V))
for o in "MOV NOT UNM LEN".split(): MODES[o] = (V, None, V)
for o in "ADDVN SUBVN MULVN DIVVN MODVN ADDNV SUBNV MULNV DIVNV MODNV".split(): MODES[o] = (V, V, N)
for o in "ADDVV SUBVV MULVV DIVVV MODVV POW CAT".split(): MODES[o] = (V, V, V)
MODES.update(KSTR=(V, None, S), KCDATA=(V, None, L), KSHORT=(V, None, SL), KNUM=(V, None, N),
             KPRI=(V, None, P), KNIL=(V, None, V), UGET=(V, None, U), USETV=(U, None, V),
             USETS=(U, None, S), USETN=(U, None, N), USETP=(U, None, P), UCLO=(V, None, J),
             FNEW=(V, None, F), TNEW=(V, None, L), TDUP=(V, None, T), GGET=(V, None, S),
             GSET=(V, None, S), TGETV=(V, V, V), TGETS=(V, V, S), TGETB=(V, V, L),
             TSETV=(V, V, V), TSETS=(V, V, S), TSETB=(V, V, L), TSETM=(V, None, N),
             CALLM=(V, L, L), CALL=(V, L, L), CALLMT=(V, None, L), CALLT=(V, None, L),
             ITERC=(V, L, L), ITERN=(V, L, L), VARG=(V, L, L), ISNEXT=(V, None, J),
             RETM=(V, None, L), RET=(V, None, L), RET0=(V, None, L), RET1=(V, None, L))
for o in "FORI JFORI FORL IFORL ITERL IITERL LOOP ILOOP JMP".split(): MODES[o] = (V, None, J)
for o in "JFORL JITERL JLOOP FUNCF IFUNCF JFUNCF FUNCV IFUNCV JFUNCV FUNCC FUNCCW".split():
    MODES[o] = (V, None, L)
PRI = {0: "nil", 1: "false", 2: "true"}


class Reader:
    def __init__(self, data, pos=0):
        self.d, self.p = data, pos

    def u8(self):
        self.p += 1
        return self.d[self.p - 1]

    def uleb(self):
        v = sh = 0
        while True:
            b = self.u8()
            v |= (b & 0x7F) << sh
            sh += 7
            if b < 0x80:
                return v

    def uleb33(self):
        b = self.u8()
        isnum = b & 1
        v, sh = b >> 1, 6
        if b & 0x80:
            v &= 0x3F
            while True:
                b = self.u8()
                v |= (b & 0x7F) << sh
                sh += 7
                if b < 0x80:
                    break
        return isnum, v

    def bytes(self, n):
        self.p += n
        return self.d[self.p - n:self.p]


def i32(v):
    return v - (1 << 32) if v >= 1 << 31 else v


class Proto:
    pass


def read_ktabk(r):
    t = r.uleb()
    if t >= 5:
        return r.bytes(t - 5).decode("latin-1")
    if t == 3:
        return i32(r.uleb())
    if t == 4:
        lo, hi = r.uleb(), r.uleb()
        return struct.unpack("<d", struct.pack("<II", lo, hi))[0]
    return {0: None, 1: False, 2: True}[t]


def parse(data):
    r = Reader(data)
    assert r.bytes(3) == b"\x1bLJ" and r.u8() == 1, "not LuaJIT 2.0 bytecode"
    flags = r.uleb()
    if not flags & 2:
        r.bytes(r.uleb())  # chunk name
    stack = []
    while True:
        plen = r.uleb()
        if plen == 0:
            break
        end = r.p + plen
        p = Proto()
        p.flags, p.nparams, p.framesize, p.nuv = r.u8(), r.u8(), r.u8(), r.u8()
        nkgc, nkn, nbc = r.uleb(), r.uleb(), r.uleb()
        dbg = 0
        if not flags & 2:
            dbg = r.uleb()
            if dbg:
                r.uleb(); r.uleb()
        p.bc = list(struct.unpack_from(f"<{nbc}I", data, r.p)); r.p += 4 * nbc
        p.uv = list(struct.unpack_from(f"<{p.nuv}H", data, r.p)); r.p += 2 * p.nuv
        kgc = []
        for _ in range(nkgc):
            t = r.uleb()
            if t == 0:
                kgc.append(stack.pop())
            elif t == 1:
                na, nh = r.uleb(), r.uleb()
                arr = [read_ktabk(r) for _ in range(na)]
                hsh = [(read_ktabk(r), read_ktabk(r)) for _ in range(nh)]
                kgc.append(("table", arr, hsh))
            elif t in (2, 3):
                kgc.append(("int64", r.uleb() | r.uleb() << 32))
            elif t == 4:
                kgc.append(("complex", [r.uleb() for _ in range(4)]))
            else:
                kgc.append(r.bytes(t - 5).decode("latin-1"))
        p.kgc = kgc[::-1]  # instructions index k.gc[~D]
        p.kn = []
        for _ in range(nkn):
            isnum, lo = r.uleb33()
            if isnum:
                hi = r.uleb()
                p.kn.append(struct.unpack("<d", struct.pack("<II", lo & 0xFFFFFFFF, hi))[0])
            else:
                p.kn.append(i32(lo))
        r.p = end
        stack.append(p)
    assert len(stack) == 1
    return stack[0]


def fmt(kind, v, p, pc):
    if kind == S:
        return repr(p.kgc[v])
    if kind == N:
        return repr(p.kn[v])
    if kind == P:
        return PRI.get(v, v)
    if kind == SL:
        return str(v - 0x10000 if v >= 0x8000 else v)
    if kind == J:
        return f"=> {pc + 1 + v - 0x8000:04d}"
    if kind == U:
        return f"uv{v}"
    if kind == F:
        return f"<function {id(p.kgc[v]):x}>"
    if kind == T:
        _, arr, hsh = p.kgc[v]
        return "{" + ", ".join([repr(a) for a in arr if a is not None] + [f"{k}={x!r}" for k, x in hsh]) + "}"
    if kind == V:
        return f"r{v}"
    return str(v)


def dump(p, out, depth=0, path="main"):
    ind = "  " * depth
    out.append(f"{ind}-- function {path}  params={p.nparams} frame={p.framesize} uv={p.nuv} "
               f"{'vararg' if p.flags & 2 else ''}")
    children = []
    for pc, ins in enumerate(p.bc):
        op = OPS[ins & 0xFF]
        a, c, b, d = (ins >> 8) & 0xFF, (ins >> 16) & 0xFF, ins >> 24, ins >> 16
        ma, mb, mc = MODES[op]
        parts = []
        if ma:
            parts.append(fmt(ma, a, p, pc))
        if mb:
            parts += [fmt(mb, b, p, pc), fmt(mc, c, p, pc)]
        else:
            parts.append(fmt(mc, d, p, pc))
        out.append(f"{ind}{pc:04d} {op:<7} {'  '.join(parts)}")
        if op == "FNEW":
            label = f"{pc:04d}"
            if pc + 1 < len(p.bc):
                nxt = p.bc[pc + 1]
                nop, na = OPS[nxt & 0xFF], (nxt >> 8) & 0xFF
                if nop in ("TSETS", "GSET") and na == a:
                    key = p.kgc[(nxt >> 16) & 0xFF] if nop == "TSETS" else p.kgc[nxt >> 16]
                    label = f"{key}@{pc:04d}"
            out[-1] += f"   -- {path}/{label}"
            children.append((label, p.kgc[d]))
    for label, child in children:
        dump(child, out, depth + 1, f"{path}/{label}")


def disassemble(data):
    out = []
    dump(parse(data), out)
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        src = Path(arg)
        src.with_suffix(".lasm").write_text(disassemble(src.read_bytes()))
