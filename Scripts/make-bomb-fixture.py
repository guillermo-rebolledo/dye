#!/usr/bin/env python3
"""Two large PNG fixtures, generated without third-party image data.

`decompression-bomb.png` is 16384 x 16384: 268 megapixels, inside the per-edge
texture limit and far outside the total-pixel limit the decoder enforces. It is what
a hostile file looks like — small enough to arrive by message, ruinous to decode.

`large-photograph.png` is 8000 x 6000, the 48 megapixels of a current phone camera.
It is the legitimate counterpart, and it is what the Preview decode is measured
against: a source far larger than any Preview of it.

Both are 8-bit truecolour of a single flat value, so deflate reduces the raster to a
few hundred kilobytes, and both are streamed a scanline at a time so generating one
costs no more memory than a single row. Truecolour rather than greyscale because a
photograph is, and because the cost a decoder pays for one is the cost under test.
"""
from pathlib import Path
import struct
import zlib

# (name, width, height): the bomb, then the legitimate 48 megapixel frame.
FIXTURES = [('decompression-bomb.png', 16384, 16384), ('large-photograph.png', 8000, 6000)]


def chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))


def png(width, height):
    # Colour type 2 is 8-bit RGB.
    header = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    # Filter byte 0 (none) followed by one row of mid grey.
    row = b'\x00' + b'\x80\x7a\x6e' * width
    deflate = zlib.compressobj(9)
    body = b''.join(deflate.compress(row) for _ in range(height)) + deflate.flush()
    # An sRGB chunk, because the decoder refuses a file whose colour space is assumed
    # rather than stated. Rendering intent 0 is perceptual.
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'sRGB', b'\x00')
            + chunk(b'IDAT', body) + chunk(b'IEND', b''))


if __name__ == '__main__':
    fixtures = Path(__file__).resolve().parent.parent / 'Tests/FilmEngineTests/Fixtures'
    for name, width, height in FIXTURES:
        data = png(width, height)
        (fixtures / name).write_bytes(data)
        print(f'{name} {len(data)} bytes for {width * height / 1e6:.0f} megapixels')
