"""icon.svg'deki 16x16 pixel-art simgeyi .ico olarak yazar (Pillow gerektirmez).

Windows EXE simgesi .ico ister; Godot SVG'yi dogrudan EXE'ye gommez.
Cikti: fps/icon.ico (16, 32, 64, 256 piksel; PNG sikistirmali ICO).
"""
import struct
import zlib
from pathlib import Path

# icon.svg ile ayni tasarim: (x, y, w, h, renk)
RECTS = [
    (0, 0, 16, 16, "1c2128"), (2, 9, 3, 5, "8a7e70"), (5, 6, 3, 8, "a9a08f"),
    (8, 4, 2, 10, "c9bfa8"), (8, 2, 2, 2, "c9bfa8"), (10, 7, 4, 7, "7b6f63"),
    (3, 10, 1, 1, "e8c96a"), (6, 8, 1, 1, "e8c96a"), (11, 9, 1, 1, "e8c96a"),
    (0, 14, 16, 2, "3b6b4a"), (6, 11, 4, 1, "c0392b"),
]


def pixels16():
    grid = [[(0, 0, 0)] * 16 for _ in range(16)]
    for x, y, w, h, color in RECTS:
        rgb = tuple(int(color[i:i + 2], 16) for i in (0, 2, 4))
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                grid[yy][xx] = rgb
    return grid


def png(size: int) -> bytes:
    grid = pixels16()
    scale = size // 16
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            r, g, b = grid[y // scale][x // scale]
            raw += bytes((r, g, b, 255))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")


def main() -> None:
    sizes = [16, 32, 48, 64, 128, 256]
    images = [png(s) for s in sizes]
    out = bytearray(struct.pack("<HHH", 0, 1, len(sizes)))
    offset = 6 + 16 * len(sizes)
    for size, data in zip(sizes, images):
        out += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
    for data in images:
        out += data
    target = Path(__file__).resolve().parents[1] / "icon.ico"
    target.write_bytes(bytes(out))
    print(target, len(out), "bayt")


if __name__ == "__main__":
    main()
