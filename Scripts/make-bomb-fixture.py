#!/usr/bin/env python3
"""A decompression bomb fixture: a small, wholly valid PNG that decodes huge.

16384 x 16384 is 268 megapixels, which is inside the per-edge texture limit and far
outside the total-pixel limit the decoder enforces. Written as 8-bit grayscale of a
single flat value so deflate reduces a 268MB raster to a few hundred kilobytes, and
streamed a scanline at a time so generating it costs no more memory than one row.
"""
from pathlib import Path
import struct
import zlib

WIDTH = HEIGHT = 16384


def chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))


def bomb():
    header = struct.pack('>IIBBBBB', WIDTH, HEIGHT, 8, 0, 0, 0, 0)
    # Filter byte 0 (none) followed by one row of mid grey.
    row = b'\x00' + b'\x80' * WIDTH
    deflate = zlib.compressobj(9)
    body = b''.join(deflate.compress(row) for _ in range(HEIGHT)) + deflate.flush()
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', body) + chunk(b'IEND', b'')


if __name__ == '__main__':
    path = Path(__file__).resolve().parent.parent / 'Tests/FilmEngineTests/Fixtures/decompression-bomb.png'
    data = bomb()
    path.write_bytes(data)
    print(f'{path} {len(data)} bytes for {WIDTH * HEIGHT / 1e6:.0f} megapixels')
