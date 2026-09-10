#!/usr/bin/env python3
"""Digitize CineStill's published 800T Cs41/Cs2 comparison, without process fitting.

Usage: digitize-cinestill-process.py manufacturer-graph.jpg output-directory
Requires PyMuPDF 1.28.2 and NumPy. The source is a pinned manufacturer JPEG;
see Curves/cinestill-800t/PROCESS-SOURCES.md for missing measurement conditions.
The logExposure coordinate is the printed chart coordinate, not an independently
verified lux-second calibration. This script does not generate a film profile.
"""
import csv
import hashlib
import pathlib
import sys

import numpy as np
import pymupdf


SOURCE_SHA256 = 'd5bd88e6a12b4ca61d0aa03b4a86ab2562563e7167612d17ff160e9be1ac2456'
# Pixel centres of the two top chart frames. Top/bottom density is 3.5/0,
# left/right log exposure is -4/+1. Legends occupy independent rectangles.
PANELS = {
    'cs41': {'x': (86.0, 563.5), 'y': (57.0, 541.5), 'legend': (400, 570, 410, 520)},
    'cs2': {'x': (665.5, 1141.0), 'y': (57.0, 541.5), 'legend': (985, 1150, 410, 520)},
}


def digitize(path, dominance=65):
    data = pathlib.Path(path).read_bytes()
    if hashlib.sha256(data).hexdigest() != SOURCE_SHA256:
        raise SystemExit('Unexpected CineStill graph edition; chart geometry must be reverified')
    pixmap = pymupdf.Pixmap(str(path))
    if (pixmap.width, pixmap.height, pixmap.n) != (1200, 1200, 3):
        raise SystemExit('Unexpected manufacturer graph pixel layout')
    pixels = np.frombuffer(pixmap.samples, np.uint8).reshape(1200, 1200, 3).astype(int)
    result = {}
    for process, panel in PANELS.items():
        x0, x1 = panel['x']
        y0, y1 = panel['y']
        curves = []
        for channel in range(3):
            others = np.max(pixels[:, :, [i for i in range(3) if i != channel]], axis=2)
            # Dominance, rather than an absolute brightness cutoff, also reads
            # the dark green curve and rejects grey axes/captions/JPEG fringes.
            mask = pixels[:, :, channel] - others > dominance
            left, right, top, bottom = panel['legend']
            mask[top:bottom, left:right] = False
            points = []
            for x in range(int(np.ceil(x0)) + 1, int(np.floor(x1))):
                ys = np.flatnonzero(mask[int(y0) + 1:int(y1), x]) + int(y0) + 1
                if len(ys) == 0 or np.max(np.diff(ys), initial=0) > 1:
                    raise SystemExit('Missing or ambiguous coloured curve at %s channel %d column %d'
                                     % (process, channel, x))
                # Centre of the coloured stroke; no monotonicity or gamma fit.
                points.append((float(x), float(ys.mean())))
            curves.append(np.array(points))
        rows = []
        for k in range(101):
            exposure = -4 + k * .05
            x = x0 + (exposure + 4) / 5 * (x1 - x0)
            # Only the chart's obscured endpoint columns use the nearest visible
            # centre (less than 0.02 log exposure); no extrapolated toe/shoulder.
            rows.append([exposure] + [(y1 - np.interp(x, curve[:, 0], curve[:, 1])) * 3.5 / (y1 - y0)
                                      for curve in curves])
        result[process] = rows
    return result


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    rows = digitize(sys.argv[1])
    out = pathlib.Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    for process, values in rows.items():
        with (out / ('process-%s.csv' % process)).open('w') as handle:
            handle.write('# CineStill 800T %s manufacturer comparison chart; printed log exposure, density; see PROCESS-SOURCES.md.\n' % process)
            writer = csv.writer(handle, lineterminator='\n')
            writer.writerow(['logExposure', 'red', 'green', 'blue'])
            writer.writerows([['%.6f' % value for value in row] for row in values])


if __name__ == '__main__':
    main()
