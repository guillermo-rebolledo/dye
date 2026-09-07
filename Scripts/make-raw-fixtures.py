#!/usr/bin/env python3
"""Synthetic uncompressed linear DNGs, generated without third-party image data."""
from pathlib import Path
import struct


def dng(value):
    width = height = 512
    # TIFF types: BYTE=1, ASCII=2, SHORT=3, LONG=4, RATIONAL=5, SRATIONAL=10.
    tags = []

    def tag(number, kind, values):
        formats = {1: 'B', 3: 'H', 4: 'I', 5: 'I', 10: 'i'}
        data = values if kind == 2 else struct.pack('<' + formats[kind] * len(values), *values)
        count = len(data) if kind == 2 else len(values) // (2 if kind in (5, 10) else 1)
        tags.append((number, kind, count, data))

    for number, kind, values in [
        (254, 4, [0]), (271, 2, b'Dye\0'), (272, 2, b'Synthetic\0'), (256, 4, [width]), (257, 4, [height]), (258, 3, [16]),
        (259, 3, [1]), (262, 3, [32803]), (273, 4, [0]), (274, 3, [1]),
        (277, 3, [1]), (278, 4, [height]), (279, 4, [width * height * 2]),
        (284, 3, [1]), (33421, 3, [2, 2]), (33422, 1, [0, 1, 1, 2]), (50706, 1, [1, 4, 0, 0]), (50707, 1, [1, 1, 0, 0]),
        (50708, 2, b'Dye synthetic linear camera\0'), (50714, 5, [0, 1]),
        (50717, 4, [65535]), (50719, 4, [0, 0]), (50720, 4, [width, height]),
        # Camera RGB equals XYZ for this synthetic camera, under D65.
        (50721, 10, [1, 1, 0, 1, 0, 1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 1, 1, 1]),
        (50728, 5, [1, 1, 1, 1, 1, 1]), (50730, 10, [0, 1]), (50778, 3, [21])
    ]:
        tag(number, kind, values)
    tags.sort()
    extra = bytearray()
    entries = bytearray()
    start = 8 + 2 + 12 * len(tags) + 4
    strip_entry = 0
    for number, kind, count, data in tags:
        entries += struct.pack('<HHI', number, kind, count)
        if number == 273:
            strip_entry = len(entries)
        if len(data) <= 4:
            entries += data.ljust(4, b'\0')
        else:
            entries += struct.pack('<I', start + len(extra))
            extra += data
            if len(extra) % 2:
                extra += b'\0'
    struct.pack_into('<I', entries, strip_entry, start + len(extra))
    return (b'II*\0' + struct.pack('<I', 8) + struct.pack('<H', len(tags)) + entries +
            b'\0' * 4 + extra + struct.pack('<H', value) * (width * height))


root = Path(__file__).resolve().parent.parent / 'Tests/FilmEngineTests/Fixtures'
for name, value in [('linear-low.dng', 8192), ('linear-high.dng', 16384)]:
    (root / name).write_bytes(dng(value))
