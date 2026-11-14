"""Convert Lord Monarch Online .MAP files to Marquis level JSON.

.MAP layout (2306 bytes):
  48*48 cell codes, column-major (byte index = x*48 + y)
  u16 theme: 10..50 -> background set B_010..B_050

A cell code is also the tile index into the theme's M sheet (BG/B_0x0M,
16x16 tiles), so codes carry both meaning and the exact edge variant.
Levels store only the meaning (one char per cell); edge variants are
rebuilt by autotiling, using the table this tool derives from all maps
(Data/lmo_autotile.json). Cells where the rebuild differs from the
original are kept as tile_overrides so converted maps render exactly.

Usage:
  python3 tools/lmo_map.py DS7E_WIN DS7E_WIN/extracted/levels Data/lmo_autotile.json
"""
import collections
import json
import re
import sys
from pathlib import Path

N = 48

# Neighbour offsets, bit order used by the mask (N, NE, E, SE, S, SW, W, NW)
DIRS = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]

# Terrain chars that autotile, and which neighbour chars count as "same".
# Map edges always count as same. Chosen by measuring agreement with the
# original maps (~99%).
AUTOTILE_SAME = {
    "~": "~=bxo*",
    "^": "^bxo*",
    "=": ".TC=bxo*",
    "T": "T",
}

# Terrain chars drawn with one fixed code
FIXED = {".": 0x00, "o": 0x05, "*": 0x06, "b": 0x7A, "x": 0x7B}

# Codes kept as objects (unknown purpose), drawn on clear land
OBJECT_CODES = {0x07, 0x10, 0x11, 0x7C, 0x7D, 0x7E}

# Castle 3x3 footprint, [row][col]; None = owner-coloured centre (0x14 + owner)
CASTLE = [[0x70, 0x74, 0x71], [0x72, None, 0x73], [0x78, 0x1D, 0x79]]


def classify(c):
    if c == 0x00 or 0x08 <= c <= 0x0F or c in OBJECT_CODES:
        return "."
    if 0x01 <= c <= 0x04:
        return "T"
    if 0x14 <= c <= 0x17 or 0x70 <= c <= 0x79 or c == 0x1D:
        return "C"
    if 0x20 <= c <= 0x2F:
        return "="
    if 0x30 <= c <= 0x5F:
        return "~"
    if 0x60 <= c <= 0x6F:
        return "^"
    for ch, code in FIXED.items():
        if c == code:
            return ch
    raise ValueError(f"unknown cell code {c:#04x}")


def read_map(path):
    d = path.read_bytes()
    if len(d) != N * N + 2:
        raise ValueError(f"{path.name}: expected {N*N+2} bytes, got {len(d)}")
    codes = [[d[x * N + y] for x in range(N)] for y in range(N)]  # [y][x]
    theme = d[N * N] | (d[N * N + 1] << 8)
    return codes, theme


def mask(terrain, x, y, same):
    m = 0
    for i, (dx, dy) in enumerate(DIRS):
        nx, ny = x + dx, y + dy
        if not (0 <= nx < N and 0 <= ny < N) or terrain[ny][nx] in same:
            m |= 1 << i
    return m


def build_autotile(all_codes):
    """Majority code per (terrain char, neighbour mask) across all maps."""
    votes = {k: collections.defaultdict(collections.Counter) for k in AUTOTILE_SAME}
    totals = {k: collections.Counter() for k in AUTOTILE_SAME}
    for codes in all_codes:
        terrain = [[classify(c) for c in row] for row in codes]
        for y in range(N):
            for x in range(N):
                t = terrain[y][x]
                if t in votes:
                    votes[t][mask(terrain, x, y, AUTOTILE_SAME[t])][codes[y][x]] += 1
                    totals[t][codes[y][x]] += 1
    return {
        "same": AUTOTILE_SAME,
        "fixed": {k: v for k, v in FIXED.items()},
        "castle": CASTLE,
        "default": {t: totals[t].most_common(1)[0][0] for t in AUTOTILE_SAME},
        "masks": {
            t: {str(m): c.most_common(1)[0][0] for m, c in sorted(v.items())}
            for t, v in votes.items()
        },
    }


def render(level, table):
    """Rebuild cell codes from a level dict. Must match Scripts/terrain_layer.gd."""
    terrain = level["terrain"]
    territory = level.get("territory")
    out = [[0] * N for _ in range(N)]
    for y in range(N):
        for x in range(N):
            t = terrain[y][x]
            if t in AUTOTILE_SAME:
                m = mask(terrain, x, y, AUTOTILE_SAME[t])
                out[y][x] = table["masks"][t].get(str(m), table["default"][t])
            elif t == "." and territory and territory[y][x] != ".":
                out[y][x] = 0x0C + int(territory[y][x])
            else:
                out[y][x] = FIXED.get(t, 0)
    for c in level["countries"]:
        cx, cy = c["castle"]
        for r in range(3):
            for col in range(3):
                code = CASTLE[r][col]
                out[cy + r][cx + col] = 0x14 + c["id"] if code is None else code
    for v in level.get("villages", []):
        x, y = v["pos"]
        out[y][x] = 0x08 + v["owner"]
    for o in level.get("objects", []):
        x, y = o["pos"]
        out[y][x] = o["code"]
    for x, y, code in level.get("tile_overrides", []):
        out[y][x] = code
    return out


def map_names(src):
    names = {}
    text = (src / "MAP" / "NAME.TXT").read_bytes().decode("shift_jis", errors="replace")
    for name, file in re.findall(r"NAME=(.*?)\r?\n(?://.*\r?\n)*FILE=(\S+)", text):
        names[file.upper()] = name.strip()
    return names


def convert(path, codes, theme, name):
    level = {
        "format": 1,
        "name": name,
        "source": f"Lord Monarch Online {path.name}",
        "theme": f"B_{theme:03d}",
        "size": [N, N],
        "day_limit": 3000,
        "player": 0,
        "countries": [],
        "terrain": [],
        "territory": [],
        "villages": [],
        "objects": [],
    }
    castles = {}
    for y in range(N):
        for x in range(N):
            c = codes[y][x]
            if 0x14 <= c <= 0x17:
                castles[c - 0x14] = [x - 1, y - 1]
            elif 0x08 <= c <= 0x0B:
                level["villages"].append({"owner": c - 0x08, "pos": [x, y]})
            elif c in OBJECT_CODES:
                level["objects"].append({"code": c, "pos": [x, y]})
    for owner in sorted(castles):
        level["countries"].append({
            "id": owner,
            "castle": castles[owner],
            "funds": 5000,
            "tax": 50,
            "control": "player" if owner == 0 else "ai",
        })
    level["terrain"] = ["".join(classify(c) for c in row) for row in codes]
    level["territory"] = [
        "".join(str(c - 0x0C) if 0x0C <= c <= 0x0F else "." for c in row) for row in codes
    ]
    if not any(set(r) - {"."} for r in level["territory"]):
        del level["territory"]
    return level


def dump_level(level):
    """JSON with one terrain row per line so maps stay readable."""
    rows = {}
    for key in ("terrain", "territory"):
        if key in level:
            rows[key] = level[key]
            level[key] = f"@@{key}@@"
    text = json.dumps(level, indent=2)
    for key, lines in rows.items():
        body = ",\n".join(f'    "{line}"' for line in lines)
        text = text.replace(f'"@@{key}@@"', "[\n" + body + "\n  ]")
        level[key] = lines
    text = re.sub(r'\{\s+"owner": (\d+),\s+"pos": \[\s+(\d+),\s+(\d+)\s+\]\s+\}',
                  r'{ "owner": \1, "pos": [\2, \3] }', text)
    text = re.sub(r'\{\s+"code": (\d+),\s+"pos": \[\s+(\d+),\s+(\d+)\s+\]\s+\}',
                  r'{ "code": \1, "pos": [\2, \3] }', text)
    text = re.sub(r'\[\s+(\d+),\s+(\d+)\s+\]', r'[\1, \2]', text)
    text = re.sub(r'\[\s+(\d+),\s+(\d+),\s+(\d+)\s+\]', r'[\1, \2, \3]', text)
    return text + "\n"


def main(src, out_dir, table_path):
    src, out_dir, table_path = Path(src), Path(out_dir), Path(table_path)
    out_dir.mkdir(parents=True, exist_ok=True)
    names = map_names(src)
    maps = [(p, *read_map(p)) for p in sorted((src / "MAP").glob("*.MAP"))]

    table = build_autotile([codes for _, codes, _ in maps])
    table_path.parent.mkdir(parents=True, exist_ok=True)
    table_path.write_text(json.dumps(table, indent=1) + "\n")

    for path, codes, theme in maps:
        level = convert(path, codes, theme, names.get(path.name.upper(), path.stem))
        rebuilt = render(level, table)
        overrides = [[x, y, codes[y][x]] for y in range(N) for x in range(N)
                     if rebuilt[y][x] != codes[y][x]]
        if overrides:
            level["tile_overrides"] = overrides
        assert render(level, table) == codes, path.name
        (out_dir / f"{path.stem}.json").write_text(dump_level(level))
        print(f"{path.name} -> {path.stem}.json  {level['name']!r} theme {level['theme']}"
              f"  overrides {len(overrides)}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
