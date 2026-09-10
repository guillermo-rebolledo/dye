#!/usr/bin/env python3
"""Draw Dye's app icon into `FilmApp/Assets.xcassets/AppIcon.appiconset`.

The mark is the three subtractive dye layers a colour film is made of, drawn as
overlapping discs that add to white where all three sit on top of one another. It
is generated rather than committed as an opaque binary so the icon has a source
the way everything else in this repository does.

Deliberately not: a film canister, a sprocketed strip, a 35mm cassette, a
manufacturer's colour trade dress, or anything else a rights holder could
recognise as theirs. See `docs/audits/app-store-readiness.md`, REL-01 and REL-13.

Standard library only, so it runs anywhere the rest of `Scripts/` does.

    python3 Scripts/make-app-icon.py
"""

import math
import pathlib
import struct
import zlib

SIZE = 1024
SUPERSAMPLE = 4
# Where the three centres sit, and how big each disc is, as a fraction of the edge.
DISC_RADIUS = 0.255
DISC_OFFSET = 0.135

# The three dye layers, in the order a colour negative stacks them.
DYES = ((0, 174, 239), (236, 0, 140), (255, 241, 0))

OUT = pathlib.Path(__file__).resolve().parent.parent / "FilmApp/Assets.xcassets/AppIcon.appiconset"


def coverage(x, y, centre_x, centre_y, radius):
    """How much of the pixel at (x, y) the disc covers, by supersampling."""
    hits = 0
    for sub_y in range(SUPERSAMPLE):
        for sub_x in range(SUPERSAMPLE):
            dx = x + (sub_x + 0.5) / SUPERSAMPLE - centre_x
            dy = y + (sub_y + 0.5) / SUPERSAMPLE - centre_y
            if dx * dx + dy * dy <= radius * radius:
                hits += 1
    return hits / (SUPERSAMPLE * SUPERSAMPLE)


def render(background, dyes):
    """One icon variant, as rows of RGB bytes.

    The discs add rather than multiply. On a near-black ground a subtractive
    rendering of the dyes would be invisible, and what the icon has to say at
    48 points is "three layers, overlapping", not "here is some colour science".
    """
    centres = []
    for index in range(3):
        angle = math.radians(-90 + index * 120)
        centres.append((SIZE * (0.5 + DISC_OFFSET * math.cos(angle)),
                        SIZE * (0.5 + DISC_OFFSET * math.sin(angle))))
    radius = SIZE * DISC_RADIUS

    rows = []
    for y in range(SIZE):
        row = bytearray()
        for x in range(SIZE):
            channels = list(background)
            for (centre_x, centre_y), dye in zip(centres, dyes):
                alpha = coverage(x, y, centre_x, centre_y, radius)
                if alpha:
                    for channel in range(3):
                        channels[channel] = min(255, channels[channel] + alpha * dye[channel])
            row.extend(int(round(value)) for value in channels)
        rows.append(bytes(row))
    return rows


def write_png(path, rows):
    """A minimal 8-bit truecolour PNG. No filtering; the images are tiny anyway."""
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    print(f"{path.relative_to(pathlib.Path.cwd())}  {path.stat().st_size:,} bytes")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # The default variant, on the deck grey the app's own surfaces use.
    write_png(OUT / "AppIcon.png", render((11, 11, 12), DYES))
    # Dark: the canvas black, so the icon recedes into a dark Home screen.
    write_png(OUT / "AppIconDark.png", render((5, 5, 5), DYES))
    # Tinted: the system supplies the hue, so this variant only carries luminance.
    grey = tuple((200, 200, 200) for _ in DYES)
    write_png(OUT / "AppIconTinted.png", render((0, 0, 0), grey))


if __name__ == "__main__":
    main()
