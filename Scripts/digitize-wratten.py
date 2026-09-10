#!/usr/bin/env python3
"""Digitize five official Kodak Wratten 2 diffuse-density plots as transmission.

Usage: digitize-wratten.py pdf-directory output-directory
Requires PyMuPDF 1.28.2. Expected filenames and SHA-256 checksums are below.
No source PDFs or chart artwork are emitted. See Curves/contrast-filters/SOURCES.md.
"""
import bisect
import csv
import hashlib
import math
import pathlib
import sys

import pymupdf


FILTERS = {
    'yellow': ('w2-8', '5975c86498145713c0a864a9c3303f8f3522140856df3a14456fe43b2b00c4d0', 61, [[75, 76, 77]]),
    'orange': ('W2-15', 'acbffbc45ce201913229fec81f3bc516b0587fe2a4b42142be01a3fcfae70a1e', 5, [[10]]),
    'red': ('W2-25', 'a7f209922fce39413a1632a53952c9c0c5dc10a4e22103812d4a272d661234bb', 61, [[75, 76, 77, 78], [79, 80], [81, 82]]),
    'green': ('W2-58', 'a2305795138fe68adac82b963b90a62b3272674bb4f5f208a6207e8b74e82beb', 61, [[75, 76, 77], [78, 79]]),
    'blue': ('W2-47', '168a816b10cf0b56ac4c0aaba50a39206c0c78e1c79f802adaa3f5bb21a02bba', 61, [[75, 76, 77], [78, 79]]),
}


def vertices(items, rotation):
    result = []
    for item in items:
        if item[0] == 'l':
            points = item[1:]
        elif item[0] == 'c':
            q = item[1:]
            points = []
            for j in range(101):
                t = j / 100
                w = [(1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3]
                points.append(pymupdf.Point(*(sum(w[k] * q[k][c] for k in range(4)) for c in range(2))))
        else:
            raise SystemExit('Unexpected primitive in pinned filter curve')
        result.extend(tuple(point * rotation) for point in points)
    return result


def extract(pdf_directory):
    values, censored = {}, {}
    for name, (filename, checksum, frame_index, groups) in FILTERS.items():
        path = pathlib.Path(pdf_directory) / (filename + '.pdf')
        if hashlib.sha256(path.read_bytes()).hexdigest() != checksum:
            raise SystemExit('Unexpected Kodak %s edition' % filename)
        document = pymupdf.open(path)
        page = document[0]
        drawings = page.get_drawings()
        frame = drawings[frame_index]['rect'] * page.rotation_matrix
        curves = []
        for group in groups:
            points = sorted(set(point for index in group
                                for point in vertices(drawings[index]['items'], page.rotation_matrix)))
            curves.append([(300 + (x - frame.x0) * 600 / frame.width,
                            (frame.y1 - y) * 3 / frame.height) for x, y in points])
        samples, bounds = [], []
        for wavelength in range(400, 701, 10):
            hits = []
            for points in curves:
                if not points[0][0] <= wavelength <= points[-1][0]:
                    continue
                i = bisect.bisect_left(points, (wavelength, -math.inf))
                if i == 0:
                    density = points[0][1]
                else:
                    (a, b), (c, d) = points[i - 1], points[i]
                    density = b + (d - b) * (wavelength - a) / (c - a)
                hits.append(density)
            if len(hits) > 1:
                raise SystemExit('Overlapping curve groups for %s at %d nm' % (name, wavelength))
            # The chart clips at D=3. Hidden curve portions are censored; 0.001
            # transmission is an explicit upper-bound approximation, not zero.
            bounded = not hits or hits[0] > 3
            density = 3 if bounded else hits[0]
            if not 0 <= density <= 3:
                raise SystemExit('Density outside the plotted range')
            samples.append(10 ** -density)
            if bounded:
                bounds.append(wavelength)
        values[name], censored[name] = samples, bounds
    return values, censored


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    values, censored = extract(sys.argv[1])
    out = pathlib.Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    with (out / 'transmittance.csv').open('w') as handle:
        handle.write('# Kodak WRATTEN 2 measured diffuse-density curves, T=10^-D; censored D>=3 uses T=0.001 upper bound. See SOURCES.md.\n')
        writer = csv.writer(handle, lineterminator='\n')
        writer.writerow(['wavelengthNM'] + list(FILTERS))
        for i, wavelength in enumerate(range(400, 701, 10)):
            writer.writerow([wavelength] + ['%.6f' % values[name][i] for name in FILTERS])
    for name, wavelengths in censored.items():
        print('%s: censored wavelengths (nm): %s' % (name, ', '.join(map(str, wavelengths)) or 'none'))


if __name__ == '__main__':
    main()
