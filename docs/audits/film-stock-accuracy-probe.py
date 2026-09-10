"""Read-only CPU probe of shipped colour grain anchors; no Metal required.

Run from any directory: python3 docs/audits/film-stock-accuracy-probe.py
This reproduces neutral-axis cube sampling and the grain envelope, not a render.
Neutral-axis tetrahedral interpolation reduces to interpolation of diagonal nodes.
"""

import json
from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parents[2]


def sample(data, start, size, coordinate):
    position = min(max(coordinate, 0), 1) * (size - 1)
    low = min(int(position), size - 2)
    fraction = position - low

    def node(index):
        offset = start + ((index * size + index) * size + index) * 8
        return struct.unpack_from('<4e', data, offset)[:3]

    return [a + fraction * (b - a) for a, b in zip(node(low), node(low + 1))]


print('Stock | middle-gray coordinate | cached gray RGB | actual gray RGB | envelope at actual gray RGB')
for path in sorted((ROOT / 'Sources/FilmEngine/Catalogue').glob('*.filmprofile')):
    data = path.read_bytes()
    assert data[:8] == b'FILMPROF'
    version, length = struct.unpack_from('<II', data, 8)
    assert version == 1
    header = json.loads(data[16:16 + length])
    profile = header['profile']
    colour = profile['colour']
    if colour.get('cubeOutput') != 'displayLinearRec2020':
        continue
    variant = next(v for v in colour['lutVariants'] if v['pushStops'] == 0)
    entry = next(e for e in header['payloads'] if e['name'] == variant['lut'])
    start = 16 + length + entry['offset']
    size = colour['lutSize']
    shaper = colour['inputShaper']
    coordinate = ((shaper['middleGrayLogExposure'] - shaper['minimumLogExposure'])
                  / (shaper['maximumLogExposure'] - shaper['minimumLogExposure']))
    base = sample(data, start, size, 0)
    cached = sample(data, start, size, .18)
    actual = sample(data, start, size, coordinate)
    response = profile['grain']['densityResponse']
    envelope = []
    enabled = all(g - b > 1e-4 for g, b in zip(cached, base))
    for value, gray, black in zip(actual, cached, base):
        if not enabled:
            envelope.append(0.0)
            continue
        t = min(max((value - black) * .5 / (gray - black), 0), 1) * 31
        low = min(int(t), 30)
        envelope.append(response[low] + (t - low) * (response[low + 1] - response[low]))
    fmt = lambda values: '/'.join(f'{v:.6f}' for v in values)
    print(f'{profile["id"]} | {coordinate:.6f} | {fmt(cached)} | {fmt(actual)} | {fmt(envelope)}')
