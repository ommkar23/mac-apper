#!/usr/bin/env python3
"""Create a deterministic, bounded PNG without third-party dependencies."""
import pathlib
import struct
import zlib

root = pathlib.Path(__file__).resolve().parents[1]
def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
rows = bytearray()
for y in range(64):
    rows.append(0)
    for x in range(64):
        rows.extend((240, 70, 40, 255) if (x // 8 + y // 8) % 2 else (30, 140, 230, 255))
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 64, 64, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(bytes(rows), 9)) + chunk(b'IEND', b'')
for relative in ['Sources/SpikeFixtures/Resources/checker.png', 'fixtures/local-checker.png', 'fixtures/SpikeAssets.xcassets/Checker.imageset/checker.png']:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)
