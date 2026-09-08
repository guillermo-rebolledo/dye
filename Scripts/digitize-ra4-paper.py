#!/usr/bin/env python3
"""Reproduce the CSV digitisation of the RA-4 paper the Print Output Stage models.
Requires PyMuPDF 1.28.2.
Usage: digitize-ra4-paper.py E-4070.pdf output-directory

The paper is a property of the darkroom rather than of any Stock, so it lives in
one shared Curve Set directory the way the Contrast Filters' transmittance table
does, and carries no stock.json. Kodak draws every chart in this publication as
vector paths, so the curves are read from the Bezier segments themselves.
No simulation/reference-project data is used.
"""
import csv
import hashlib
import pathlib
import sys

import pymupdf

SHA256 = '6f632cc5943a4adb8da487b86470ddf51c436a52f313241691b5b8b2bab1718f'
PUBLICATION = 'Kodak E-4070, March 2013'
WAVELENGTHS = list(range(400, 701, 10))

# Plot geometry measured from the pinned PDF's own drawn chart frames, as
# (pixel at value0, pixel at value1, value0, value1), with the drawing index of
# each curve on its page.
CHARACTERISTIC = {'page': 4, 'curves': {'red': 8, 'green': 9, 'blue': 10},
                  'x': (364.68, 549.21, -3.0, 0.0), 'y': (257.17, 72.55, 0.0, 3.0)}
SENSITIVITY = {'page': 4, 'curves': {'red': 17, 'green': 16, 'blue': 15},
               'x': (350.59, 551.08, 250, 750), 'y': (391.53, 315.74, 0.0, 2.0)}
DYE = {'page': 5, 'curves': {'cyan': 26, 'magenta': 27, 'yellow': 28},
       'x': (76.83, 261.26, 400, 700), 'y': (270.92, 86.57, 0.0, 2.5)}


def bezier(items):
    points = []
    for item in items:
        if item[0] == 'l':
            points.extend((p.x, p.y) for p in item[1:])
        elif item[0] == 'c':
            q = item[1:]
            for j in range(101):
                t = j / 100
                w = [(1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3]
                points.append(tuple(sum(w[k] * q[k][c] for k in range(4)) for c in range(2)))
    return sorted(set(points))


def linear(value, span):
    p0, p1, v0, v1 = span
    return v0 + (value - p0) * (v1 - v0) / (p1 - p0)


def pixel(value, span):
    p0, p1, v0, v1 = span
    return p0 + (value - v0) * (p1 - p0) / (v1 - v0)


def at(points, x, absent=False):
    if x < points[0][0] or x > points[-1][0]:
        return None if absent else points[0 if x < points[0][0] else -1][1]
    for (a, b), (c, d) in zip(points, points[1:]):
        if a <= x <= c:
            return b + (d - b) * (x - a) / (c - a) if c > a else b
    return points[-1][1]


def rising(values):
    """Paper density only rises with exposure. A drawn stroke's own curvature
    dips by a thousandth of a density where the curve is flat, which is not a
    measurement the paper curve can be a response to."""
    out = []
    for v in values:
        out.append(max(v, out[-1]) if out else v)
    return out


def curves(page, spec):
    return {name: [(linear(px, spec['x']), linear(py, spec['y'])) for px, py in bezier(page[index]['items'])]
            for name, index in spec['curves'].items()}


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    pdf, output = sys.argv[1:]
    if hashlib.sha256(pathlib.Path(pdf).read_bytes()).hexdigest() != SHA256:
        raise SystemExit('Expected %s; chart layouts differ between editions' % PUBLICATION)
    document = pymupdf.open(pdf)
    out = pathlib.Path(output)
    out.mkdir(parents=True, exist_ok=True)

    def write(name, source, header, rows):
        with (out / name).open('w') as handle:
            handle.write('# %s, %s; vector-path digitisation. See SOURCES.md.\n' % (PUBLICATION, source))
            writer = csv.writer(handle, lineterminator='\n')
            writer.writerow(header)
            writer.writerows([[('%.6f' % v) if isinstance(v, float) else v for v in row] for row in rows])

    # The paper's own D-logE curves, on a uniform 101-sample grid over the drawn
    # span. Exposure is physical log10 lux-seconds at the paper and density is
    # Status A reflection density including the paper's D-min.
    drawn = curves(document[CHARACTERISTIC['page'] - 1].get_drawings(), CHARACTERISTIC)
    v0, v1 = CHARACTERISTIC['x'][2], CHARACTERISTIC['x'][3]
    grid = [v0 + k * (v1 - v0) / 100 for k in range(101)]
    channels = {name: rising([at(points, x) for x in grid]) for name, points in drawn.items()}
    write('density.csv', 'page 4 Characteristic Curves', ['logExposure', 'red', 'green', 'blue'],
          [[grid[k]] + [channels[name][k] for name in ('red', 'green', 'blue')] for k in range(101)])

    # Which light each layer answers to. Outside a layer's drawn path the model
    # uses zero, an assumption rather than a measurement of the unplotted tail.
    drawn = curves(document[SENSITIVITY['page'] - 1].get_drawings(), SENSITIVITY)
    rows = []
    for nm in WAVELENGTHS:
        row = [nm]
        for name in ('red', 'green', 'blue'):
            value = at(drawn[name], nm, absent=True)
            row.append(0.0 if value is None else 10 ** value)
        rows.append(row)
    write('sensitivity.csv', 'page 4 Spectral-Sensitivity Curves', ['wavelengthNM', 'red', 'green', 'blue'], rows)

    # The dyes the paper forms, peak-normalised as Kodak draws them. Their
    # amplitudes come from the characteristic curves rather than from the chart.
    drawn = curves(document[DYE['page'] - 1].get_drawings(), DYE)
    write('dye-density.csv', 'page 5 Spectral-Dye-Density Curves', ['wavelengthNM', 'cyan', 'magenta', 'yellow'],
          [[nm] + [max(0.0, at(drawn[name], nm)) for name in ('cyan', 'magenta', 'yellow')] for nm in WAVELENGTHS])


if __name__ == '__main__':
    main()
