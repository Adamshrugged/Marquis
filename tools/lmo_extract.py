"""Extract Lord Monarch Online (DS7E_WIN) graphics to PNG.

Formats (reverse-engineered from DS7E_WIN.EXE):
  *.256 + *.PAL   u32 w, u32 h, 8-bit pixels; palette = 256 x (R,G,B,X)
  BG/*.BZ         compressed -> 256 tiles 16x16, 4-bit planar + 16-color palette
  CHR/*.BZ        same data; C_xxxL* tiles grouped 4 at a time into 32x32 sprites (TL,TR,BL,BR)
  DATA/DATA1.BZ   compressed -> 512x512 8-bit, palette DATA1.RGB (R,G,B,X)

BZ tile payload: 32768 bytes of tiles (4 planes x 16 rows x 2 bytes each),
then 48-byte palette: 16 x (B,R,G), 4 bits per channel.

Usage: python3 tools/lmo_extract.py DS7E_WIN DS7E_WIN/extracted
"""
import struct
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from lmo_bz import decompress  # noqa: E402

TILE_BYTES = 128


def bz_palette(trailer):
    pal = []
    for i in range(16):
        b, r, g = trailer[i * 3:i * 3 + 3]
        pal += [r * 17, g * 17, b * 17]
    return pal + [0] * (768 - len(pal))


def decode_tile(px, index):
    base = index * TILE_BYTES
    out = bytearray(256)
    for y in range(16):
        for x in range(16):
            byte_i, bit = base + y * 2 + x // 8, 7 - (x % 8)
            v = 0
            for p in range(4):
                v |= ((px[byte_i + p * 32] >> bit) & 1) << p
            out[y * 16 + x] = v
    return Image.frombytes("P", (16, 16), bytes(out))


def bz_sheet(data, sprite):
    px, pal = data[:32768], bz_palette(data[32768:32816])
    im = Image.new("P", (256, 256))
    for t in range(256):
        if sprite:  # 32x32 blocks, 8 per row
            blk, k = divmod(t, 4)
            x = (blk % 8) * 32 + (k % 2) * 16
            y = (blk // 8) * 32 + (k // 2) * 16
        else:
            x, y = (t % 16) * 16, (t // 16) * 16
        im.paste(decode_tile(px, t), (x, y))
    im.putpalette(pal)
    return im


def rgbx_palette(raw):
    pal = []
    for i in range(min(256, len(raw) // 4)):
        pal += list(raw[i * 4:i * 4 + 3])
    return pal + [0] * (768 - len(pal))


def convert_256(src, out):
    for img_path in sorted((src / "DATA").glob("*.256")):
        data = img_path.read_bytes()
        w, h = struct.unpack_from("<II", data, 0)
        pal_path = img_path.with_suffix(".PAL")
        if not pal_path.exists():
            continue
        im = Image.frombytes("P", (w, h), data[8:8 + w * h])
        im.putpalette(rgbx_palette(pal_path.read_bytes()))
        im.convert("RGB").save(out / f"{img_path.stem}.png")
        print(f"{img_path.name} -> {img_path.stem}.png ({w}x{h})")


def main(src, out):
    src, out = Path(src), Path(out)
    for sub in ("BG", "CHR", "DATA"):
        (out / sub).mkdir(parents=True, exist_ok=True)

    for folder in ("BG", "CHR"):
        for f in sorted((src / folder).glob("*.BZ")):
            # only the large unit sprites (C_xxxL1-4) are 32x32
            sprite = folder == "CHR" and f.stem[5] == "L"
            im = bz_sheet(decompress(f.read_bytes()), sprite)
            if folder == "CHR":
                # Unit sprites: the top-left pixel's colour is the background
                im.info["transparency"] = im.getpixel((0, 0))
                im.convert("RGBA").save(out / folder / f"{f.stem}.png")
            else:
                im.convert("RGB").save(out / folder / f"{f.stem}.png")
            print(f"{folder}/{f.name} -> {f.stem}.png")

    data1 = decompress((src / "DATA" / "DATA1.BZ").read_bytes())
    im = Image.frombytes("P", (512, 512), data1)
    im.putpalette(rgbx_palette((src / "DATA" / "DATA1.RGB").read_bytes()))
    im.convert("RGB").save(out / "DATA" / "DATA1.png")
    print("DATA/DATA1.BZ -> DATA1.png")

    convert_256(src, out / "DATA")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
