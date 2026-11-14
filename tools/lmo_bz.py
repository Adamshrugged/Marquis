"""Decompress Lord Monarch Online .BZ files.

Ported from DS7E_WIN.EXE (0x41fe40 chunk loop, 0x420240 bit-mode decoder).

File = chunks. Each chunk: u16 size (counts itself), payload, then u8 flag
(non-zero = another chunk follows). Payload starting with 0x00 is the
bit-flag LZ77 mode; anything else is the byte-opcode mode (0x41fef0), which
no shipped file uses.

Usage: python3 -I lmo_bz.py <in.BZ> [<out.bin>]
"""
import sys


class _Bits:
    def __init__(self, data, pos):
        self.d = data
        # mode byte 0x00, then a single byte seeds the first 8 flag bits
        self.buf = data[pos + 1]
        self.n = 8
        self.pos = pos + 2

    def byte(self):
        b = self.d[self.pos]
        self.pos += 1
        return b

    def bit(self):
        if self.n == 0:
            self.buf = self.d[self.pos] | (self.d[self.pos + 1] << 8)
            self.pos += 2
            self.n = 16
        self.n -= 1
        b = self.buf & 1
        self.buf >>= 1
        return b

    def bits(self, count):
        v = 0
        for _ in range(count):
            v = (v << 1) | self.bit()
        return v


def _decode_chunk(data, pos, out):
    r = _Bits(data, pos)
    while True:
        if not r.bit():
            out.append(r.byte())
            continue
        if not r.bit():
            offset = r.byte()
        else:
            offset = (r.bits(5) << 8) | r.byte()
            if offset == 0:
                return r.pos
            if offset == 1:
                if not r.bit():
                    n = r.bits(4)
                else:
                    n = (r.bits(4) << 8) | r.byte()
                fill = r.byte()
                out.extend([fill] * (n + 14))
                continue
        if r.bit():
            length = 2
        elif r.bit():
            length = 3
        elif r.bit():
            length = 4
        elif r.bit():
            length = 5
        elif not r.bit():
            length = r.byte() + 14
        else:
            length = r.bits(3) + 6
        start = len(out) - offset
        for i in range(length):
            out.append(out[start + i])


def decompress(data):
    out = bytearray()
    pos = 0
    while True:
        size = data[pos] | (data[pos + 1] << 8)
        chunk_start = pos
        pos += 2
        if data[pos] != 0:
            raise ValueError("byte-opcode mode not implemented")
        _decode_chunk(data, pos, out)
        pos = chunk_start + size
        if pos >= len(data) or data[pos] == 0:
            return bytes(out)
        pos += 1


if __name__ == "__main__":
    raw = open(sys.argv[1], "rb").read()
    res = decompress(raw)
    print(f"{sys.argv[1]}: {len(raw)} -> {len(res)} bytes")
    if len(sys.argv) > 2:
        open(sys.argv[2], "wb").write(res)
