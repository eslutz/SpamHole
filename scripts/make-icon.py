"""Render the simple editable SpamHole logo without image-library dependencies."""
import struct
import zlib
from pathlib import Path

size = 1024
dark, teal = (16, 27, 42), (60, 215, 193)
rows = bytearray()
for y in range(size):
    rows.append(0)
    for x in range(size):
        distance = ((x - 512) ** 2 + (y - 490) ** 2) ** .5
        ring = 182 < distance <= 295
        # The logo's rounded lower stem.
        rx = max(abs(x - 512) - 24, 0)
        ry = max(abs(y - 776) - 20, 0)
        stem = rx * rx + ry * ry <= 36 * 36
        rows.extend(teal if ring or stem else dark)

def chunk(kind, data):
    return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))

png = b'\x89PNG\r\n\x1a\n'
png += chunk(b'IHDR', struct.pack('!2I5B', size, size, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b'')
Path('App/Assets.xcassets/AppIcon.appiconset/AppIcon.png').write_bytes(png)
