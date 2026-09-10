#!/usr/bin/env python3
"""Reproduce the Kodak/CIE CSV digitisation for the KODAK VISION3 ECN-2 stocks.
Requires PyMuPDF 1.28.2, and NumPy for the one stock that needs it.

Usage: digitize-vision3.py vision3-50d  H-1-5203t.pdf CIE_xyz.csv CIE_d65.csv output-directory
       digitize-vision3.py vision3-200t H-1-5213t.pdf CIE_xyz.csv CIE_d65.csv output-directory
       digitize-vision3.py vision3-500t H-1-5219t.pdf CIE_xyz.csv CIE_d65.csv output-directory
       digitize-vision3.py vision3-250d H-1-5207.pdf H-1-5203t.pdf CIE_xyz.csv CIE_d65.csv output-directory

50D, 200T and 500T are the July 2015 edition of one publication family and draw
every chart as vector paths, so their curves are read from the Bezier segments
themselves. Kodak's current 250D sheet is a later, differently typeset edition
that draws its charts as raster plates, so those are recovered from ink pixels
the way the Fujichrome sheets are; it supplies that stock's Characteristic
Curves and MTF, and 250D takes its two spectral charts from 50D's sheet, which
is why that invocation needs both. See each Curve Set's SOURCES.md.
No simulation/reference-project data is used.
"""
import csv
import hashlib
import math
import pathlib
import sys

import pymupdf

WAVELENGTHS = list(range(400, 701, 10))
MTF_SAMPLES = [3, 5, 10, 20, 30, 40, 50, 60, 70, 80]

# Plot geometry measured from each pinned PDF's own drawn chart frame, in PDF
# points. `characteristic`/`sensitivity`/`dye`/`mtf` name the page (1-based, as
# the datasheet prints it) and the drawing index of each curve on it.
#
# 500T's numbers are the ones this script's single-stock predecessor carried, so
# the CSVs it wrote reproduce byte for byte.
STOCKS = {
    'vision3-50d': {
        'sha256': 'adf0dedd974323b4e5d53a54023cd72bc85f447f5f814eb7882774c145d10eeb',
        'publication': 'Kodak H-1-5203t, revised 7-15',
        'kind': 'vector',
        'characteristic': {'page': 4, 'curves': {'red': 74, 'green': 75, 'blue': 76},
                           'x': (356.14, 540.60, -3.03, 2.006), 'y': (306.78, 122.29, 0.0, 3.0)},
        'sensitivity': {'page': 4, 'curves': {'red': 92, 'green': 91, 'blue': 93},
                        'x': (352.66, 553.25, 250, 750), 'zero': 665.67, 'decade': 37.85},
        'dye': {'page': 5, 'curves': {'minimum': 32, 'midscale': 33},
                'x': (81.35, 265.76, 400, 800), 'zero': 338.784, 'unit': 92.18},
        'mtf': {'page': 3, 'curves': {'red': 47, 'green': 45, 'blue': 46},
                'origin': 360.68, 'decade': 71.168, 'zero': 489.90, 'response': 66.478},
    },
    'vision3-200t': {
        'sha256': 'c2a88cb5de19c40e991f7522f9c7a43ea4c59357ccdca6957a4f5e31f2abd411',
        'publication': 'Kodak H-1-5213t, revised 7-15',
        'kind': 'vector',
        'characteristic': {'page': 4, 'curves': {'red': 62, 'green': 63, 'blue': 64},
                           'x': (357.49, 542.08, -3.684, 1.116), 'y': (304.92, 120.44, 0.0, 3.0)},
        'sensitivity': {'page': 4, 'curves': {'red': 102, 'green': 100, 'blue': 101},
                        'x': (351.13, 551.67, 250, 750), 'zero': 664.02, 'decade': 37.86},
        'dye': {'page': 5, 'curves': {'minimum': 29, 'midscale': 28},
                'x': (77.90, 262.19, 400, 800), 'zero': 337.897, 'unit': 92.215},
        'mtf': {'page': 3, 'curves': {'red': 51, 'green': 50, 'blue': 49},
                'origin': 360.71, 'decade': 72.901, 'zero': 516.43, 'response': 66.657},
    },
    'vision3-500t': {
        'sha256': '06eca2287fbaf57a1aeacbb8151bbd48e23aefb30af2114b412e9c1c63f4d1db',
        'publication': 'Kodak H-1-5219t, revised 7-15',
        'kind': 'vector',
        'characteristic': {'page': 4, 'curves': {'red': 95, 'green': 93, 'blue': 94},
                           'x': (353.63, 538.15, -4.0, 1.0), 'y': (306.79, 122.30, 0.0, 3.0)},
        'sensitivity': {'page': 4, 'curves': {'red': 112, 'green': 111, 'blue': 110},
                        'x': (353.30, 553.80, 250, 750), 'zero': 669.78, 'decade': 37.855},
        'dye': {'page': 5, 'curves': {'minimum': 32, 'midscale': 31},
                'x': (81.57, 265.89, 400, 800), 'zero': 321.52, 'unit': 92.26},
        # Peak-normalized dye+mask density differences. Preserve the small
        # negative lobes on the printed chart; these are not absolute absorption.
        'isolatedDye': {'page': 5, 'curves': {'cyan': 30, 'magenta': 29, 'yellow': 28}},
        'granularity': {'page': 4, 'densityCurves': {'red': 47, 'green': 46, 'blue': 45},
                        # Green and red share one drawing, as separate subpaths.
                        'grainCurves': {'red': (49, 116, 232), 'green': (49, 0, 116),
                                        'blue': (48, 0, 84)},
                        'densityY': (345.05, 161.199, 0.0, 3.0),
                        'sigmaTicks': list(range(50, 65)),
                        'sigmaValues': [.001, .002, .003, .004, .005, .006, .007,
                                        .008, .009, .01, .02, .03, .04, .05, .10],
                        'densityGrid': [0.95 + k * 0.01 for k in range(106)]},
        'mtf': {'page': 3, 'curves': {'red': 44, 'green': 45, 'blue': 46},
                'origin': 362.59, 'decade': 72.90, 'zero': 489.82, 'response': 66.49},
    },
    'vision3-250d': {
        'sha256': '69094a9cecdfe2fae752a96c1f471bddf1cb514c83513757b6587a3de6432799',
        'publication': 'Kodak H-1-5207, March 2022',
        'kind': 'raster',
        # Raster plates carry no drawing index; each chart names the image xref
        # its page draws, and its axes are calibrated from the plate's own frame
        # and grid lines rather than from PDF coordinates.
        'characteristic': {'page': 3, 'xref': 9, 'coverage': 0.6,
                           'x': [-3.7, 1.1], 'y': [3.0, 0.0],
                           # The exposure caption and the three axis ticks the
                           # chart draws inside its own frame, in chart units.
                           'exclusions': [(-3.7, 0.10, 2.40, 3.00), (-3.7, -3.54, 0.90, 2.10)],
                           'tolerance': 0.09, 'step': 0.048},
        'mtf': {'page': 3, 'xref': 10, 'coverage': 0.5,
                'x': [1, 2, 3, 4, 5, 10, 20, 50, 100, 200, 600],
                'y': [200, 100, 70, 50, 30, 20, 10, 7, 5, 3, 2, 1],
                # The minor ticks the log axes draw inside the frame: a column
                # of them at the left edge, and a row of them along the bottom.
                'exclusions': [(1, 1.3, 1.0, 200.0), (1, 600, 1.0, 1.5)], 'tolerance': 10.0},
        # This edition's Spectral Sensitivity and Spectral Dye Density plates draw
        # curves that cross one another in one colour, and no separation of them is
        # reliable enough to call a measurement. 250D borrows them from 50D, the
        # other daylight VISION3 stock, exactly as Velvia borrows Provia's dye set,
        # and marks both artistic. See Curves/vision3-250d/SOURCES.md.
        'borrows': 'vision3-50d',
    },
}


def open_pinned(stock, path):
    if hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest() != STOCKS[stock]['sha256']:
        raise SystemExit('Unexpected %s datasheet edition; chart layouts differ between editions'
                         % STOCKS[stock]['publication'])
    return pymupdf.open(path)


def bezier(items):
    """Vector path vertices, cubic segments resampled at 101 points."""
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


def at(points, x, absent=False):
    """The drawn path at one horizontal coordinate, holding its endpoints unless
    the caller wants what the chart leaves undrawn reported as absent."""
    if x < points[0][0] or x > points[-1][0]:
        return None if absent else points[0 if x < points[0][0] else -1][1]
    for (a, b), (c, d) in zip(points, points[1:]):
        if a <= x <= c:
            return b + (d - b) * (x - a) / (c - a) if c > a else b
    return points[-1][1]


def linear(pixel, span):
    """A chart axis given as (pixel at value0, pixel at value1, value0, value1)."""
    p0, p1, v0, v1 = span
    return v0 + (pixel - p0) * (v1 - v0) / (p1 - p0)


def pixel(value, span):
    """The inverse: where on the page one axis value sits."""
    p0, p1, v0, v1 = span
    return p0 + (value - v0) * (p1 - p0) / (v1 - v0)


def rising(points):
    """A colour negative's density only rises as exposure does. Both branches
    hold it to that: a drawn stroke's own curvature dips by a thousandth of a
    density in a flat toe, and a raster run centre wanders by a pixel there,
    and neither is a measurement the Film Response can be a response to."""
    out = []
    for across, density in points:
        out.append((across, max(density, out[-1][1]) if out else density))
    return out


def vector_characteristic(document, spec):
    """Density against log exposure per layer, on a uniform 101-sample grid over
    the chart's own plotted span. Coordinates are physical log10 lux-seconds and
    density including base density."""
    chart = spec['characteristic']
    page = document[chart['page'] - 1].get_drawings()
    v0, v1 = chart['x'][2], chart['x'][3]
    step = (v1 - v0) / 100
    curves = {}
    for name, index in chart['curves'].items():
        points = [(linear(px, chart['x']), linear(py, chart['y'])) for px, py in bezier(page[index]['items'])]
        curves[name] = rising([(v0 + k * step, at(points, v0 + k * step)) for k in range(101)])
    return curves


def vector_sensitivity(document, spec):
    """Log sensitivity against wavelength, converted to linear sensitivity.
    Outside a layer's drawn path the model uses zero, which is an assumption
    rather than a measurement of the unplotted tail."""
    chart = spec['sensitivity']
    page = document[chart['page'] - 1].get_drawings()
    curves = {name: bezier(page[index]['items']) for name, index in chart['curves'].items()}
    rows = []
    for nm in WAVELENGTHS:
        row = [nm]
        for name in ('red', 'green', 'blue'):
            drawn = at(curves[name], pixel(nm, chart['x']), absent=True)
            row.append(0.0 if drawn is None else 10 ** ((chart['zero'] - drawn) / chart['decade']))
        rows.append(row)
    return rows


def vector_dye(document, spec):
    """Aggregate minimum and midscale neutral spectral density. Kept separate
    from any individual dye curves the same datasheet also publishes."""
    chart = spec['dye']
    page = document[chart['page'] - 1].get_drawings()
    curves = {name: bezier(page[index]['items']) for name, index in chart['curves'].items()}
    return [[nm] + [(chart['zero'] - at(curves[name], pixel(nm, chart['x']))) / chart['unit']
                    for name in ('minimum', 'midscale')] for nm in WAVELENGTHS]


def vector_isolated_dye(document, spec):
    """Individual peak-normalized dye curves on the aggregate chart's axes.
    Do not clamp or renormalize: signed lobes and printed normalization error
    belong to the source, not to an invented nonnegative isolated absorber."""
    chart, axis = spec['isolatedDye'], spec['dye']
    page = document[chart['page'] - 1].get_drawings()
    curves = {name: bezier(page[index]['items']) for name, index in chart['curves'].items()}
    rows = []
    for nm in WAVELENGTHS:
        values = [at(curves[name], pixel(nm, axis['x']), absent=True)
                  for name in ('cyan', 'magenta', 'yellow')]
        if any(value is None for value in values):
            raise SystemExit('An isolated dye curve does not cover the requested wavelength grid')
        rows.append([nm] + [(axis['zero'] - value) / axis['unit'] for value in values])
    return rows


def vector_granularity(document, spec):
    """Read Kodak's nomograph at equal absolute density, independently per RGB.

    The x-axis is relative exposure, not the physical exposure of the separate
    sensitometry chart. Follow density to the solid channel curve, then vertically
    to that channel's dashed grain curve, then read sigma-D on the right log axis.
    Only emit densities inside all three drawn ranges; no endpoint extrapolation.
    """
    chart = spec['granularity']
    page = document[chart['page'] - 1].get_drawings()
    ticks = [(page[index]['rect'].y0 + page[index]['rect'].y1) / 2
             for index in chart['sigmaTicks']]
    logs = [math.log10(value) for value in chart['sigmaValues']]
    mean_y, mean_log = sum(ticks) / len(ticks), sum(logs) / len(logs)
    slope = sum((y - mean_y) * (v - mean_log) for y, v in zip(ticks, logs)) / sum(
        (y - mean_y) ** 2 for y in ticks)
    intercept = mean_log - slope * mean_y
    if max(abs(slope * y + intercept - v) for y, v in zip(ticks, logs)) > 0.001:
        raise SystemExit('Granularity log-axis ticks do not match the pinned chart calibration')

    density_curves, grain_curves = {}, {}
    for name in ('red', 'green', 'blue'):
        points = bezier(page[chart['densityCurves'][name]]['items'])
        density_curves[name] = sorted((linear(y, chart['densityY']), x) for x, y in points)
        index, first, last = chart['grainCurves'][name]
        items = page[index]['items'][first:last]
        if len(items) != last - first or any(a[-1] != b[1] for a, b in zip(items, items[1:])):
            raise SystemExit('A granularity subpath is not the expected continuous curve')
        grain_curves[name] = bezier(items)

    rows = []
    for density in chart['densityGrid']:
        row = [density]
        for name in ('red', 'green', 'blue'):
            x = at(density_curves[name], density, absent=True)
            y = None if x is None else at(grain_curves[name], x, absent=True)
            if y is None:
                raise SystemExit('Granularity sample lies outside a measured nomograph curve')
            row.append(10 ** (slope * y + intercept))
        rows.append(row)
    return rows


def vector_mtf(document, spec):
    """Modulation transfer on logarithmic frequency and response axes, stored as
    ratios rather than percent."""
    chart = spec['mtf']
    page = document[chart['page'] - 1].get_drawings()
    curves = {name: bezier(page[index]['items']) for name, index in chart['curves'].items()}
    return [[n] + [10 ** ((chart['zero'] - at(curves[name], chart['origin'] + math.log10(n) * chart['decade']))
                          / chart['response']) / 100 for name in ('red', 'green', 'blue')]
            for n in MTF_SAMPLES]


# --- The raster branch -------------------------------------------------------
#
# Kodak's current 250D sheet prints its charts as antialiased raster plates. The
# helpers below recover curves from ink pixels; `rules`, `calibrate`, `runs`,
# `plot`, `readable`, `track` and `resample` are the same operations
# Scripts/digitize-fujichrome.py performs on the Fujichrome plates, adapted for
# grey rather than 1-bit ink and for a plate whose printed captions sit inside
# its own frame.


def ink(document, xref, threshold=128):
    import numpy as np
    pixmap = pymupdf.Pixmap(document, xref)
    samples = np.frombuffer(pixmap.samples, dtype=np.uint8).reshape(pixmap.height, pixmap.width, pixmap.n)
    return samples.mean(2) < threshold


def frame_ink(mask):
    """Ink connected to the chart's own frame. Every curve either runs to the
    frame or crosses a rule that meets it, and every printed caption inside the
    plot area is a component of its own, so this drops the captions without
    naming a rectangle for each of them."""
    import numpy as np
    parent = []

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    rows, previous = [], []
    for y in range(mask.shape[0]):
        index = np.flatnonzero(mask[y])
        row, start = [], None
        for i, x in enumerate(index):
            if start is None:
                start = x
            if i + 1 == len(index) or index[i + 1] != x + 1:
                row.append((start, x, len(parent)))
                parent.append(len(parent))
                start = None
        for a0, a1, ai in previous:
            for b0, b1, bi in row:
                if b0 <= a1 + 1 and a0 <= b1 + 1:
                    ra, rb = find(ai), find(bi)
                    if ra != rb:
                        parent[rb] = ra
        rows.append(row)
        previous = row
    weight = {}
    for row in rows:
        for x0, x1, i in row:
            weight[find(i)] = weight.get(find(i), 0) + x1 - x0 + 1
    largest = max(weight, key=weight.get)
    out = np.zeros_like(mask)
    for y, row in enumerate(rows):
        for x0, x1, i in row:
            if find(i) == largest:
                out[y, x0:x1 + 1] = True
    return out


def rules(mask, axis, coverage):
    """Spans of the chart's frame and grid lines: the only rows or columns a
    printed chart draws all the way across itself."""
    length = mask.shape[1 - axis]
    hits = [i for i, count in enumerate(mask.sum(1 - axis)) if count > coverage * length]
    if not hits:
        raise SystemExit('No grid lines found; the plate layout differs from the pinned edition')
    groups = [[hits[0]]]
    for i in hits[1:]:
        if i - groups[-1][-1] <= 3:
            groups[-1].append(i)
        else:
            groups.append([i])
    return [(g[0] + g[-1]) / 2 for g in groups]


def calibrate(centres, labels, log=False):
    """Least-squares pixel-to-value map. A grid line the curves interrupt simply
    goes undetected, so each detected line is snapped to the nearest printed
    label rather than assumed to be the n-th of them."""
    import numpy as np
    values = [math.log10(v) for v in labels] if log else [float(v) for v in labels]
    span = (values[-1] - values[0]) / (centres[-1] - centres[0])
    snapped = [min(values, key=lambda v: abs(v - (values[0] + span * (c - centres[0])))) for c in centres]
    if len(set(snapped)) != len(snapped):
        raise SystemExit('Ambiguous axis calibration; the plate layout differs from the pinned edition')
    slope, intercept = np.polyfit(centres, snapped, 1)
    return lambda pixel: (10 ** (slope * pixel + intercept)) if log else slope * pixel + intercept


def runs(column, gap=4):
    """Ink runs down one pixel column, as centres. A drawn curve is several
    pixels thick, and two curves that have not yet separated are one run."""
    import numpy as np
    index = np.flatnonzero(column)
    if len(index) == 0:
        return []
    out, start, previous = [], index[0], index[0]
    for i in index[1:]:
        if i - previous > gap:
            out.append((start + previous) / 2)
            start = i
        previous = i
    out.append((start + previous) / 2)
    return out


def readable(mask, x, y, coverage, exclusions):
    """Run centres in chart coordinates, top of the chart first, with the frame
    and grid lines removed and the ticks and captions the caller names dropped."""
    import numpy as np
    horizontal, vertical = rules(mask, 0, coverage), rules(mask, 1, coverage)
    cleared = mask.copy()
    cleared[:int(horizontal[0]) + 4, :] = False
    cleared[max(0, int(horizontal[-1]) - 3):, :] = False
    for rule in horizontal:
        cleared[max(0, int(rule) - 3):int(rule) + 4, :] = False
    skip = np.zeros(mask.shape[1], bool)
    skip[:int(vertical[0]) + 4] = True
    skip[max(0, int(vertical[-1]) - 3):] = True
    for rule in vertical:
        skip[max(0, int(rule) - 3):int(rule) + 4] = True
    out = {}
    for column in range(mask.shape[1]):
        if skip[column]:
            continue
        across = x(column + 0.5)
        values = [v for v in (y(centre) for centre in runs(cleared[:, column]))
                  if not any(a <= across <= b and c <= v <= d for a, b, c, d in exclusions)]
        if values:
            out[across] = sorted(values, reverse=True)
    return out


def track(columns, count, tolerance):
    """Follow `count` curves across a chart that draws them in one colour, in
    both directions from the first column that separates them all. Each curve
    continues to the run nearest where it was; a column that offers nothing that
    near is left to the interpolation between the columns that do. Only for
    curves that never change places, which the three layers of a colour
    negative's sensitometry do not."""
    import numpy as np
    keys = sorted(columns)
    start = next((k for k in keys if len(columns[k]) >= count), None)
    if start is None:
        raise SystemExit('The chart never separates its curves; the layout differs from the pinned edition')
    tracks = [{start: v} for v in columns[start][:count]]
    for forwards in (True, False):
        ordered = [k for k in keys if k >= start] if forwards else [k for k in reversed(keys) if k <= start]
        held = [[columns[start][i]] for i in range(count)]
        for key in ordered[1:]:
            for i, points in enumerate(held):
                nearest = min(columns[key], key=lambda v: abs(v - points[-1]))
                if abs(nearest - points[-1]) <= tolerance:
                    tracks[i][key] = nearest
                    points.append(nearest)
    return [np.array(sorted(t.items())) for t in tracks]


def resample(curve, grid, window):
    """A curve on `grid`, each sample the mean of the tracked points within
    `window` of it. A run centre wanders by a pixel or two as a printed stroke's
    edge frays, and reading one column per sample keeps that jitter — which is
    inside the stroke width, but is a corner the Colour Cube then has to follow
    and cannot."""
    import numpy as np
    out = []
    for x in grid:
        near = curve[np.abs(curve[:, 0] - x) <= window]
        out.append((float(x), float(near[:, 1].mean()) if len(near)
                    else float(np.interp(x, curve[:, 0], curve[:, 1]))))
    return out


def raster_characteristic(document, spec):
    import numpy as np
    chart = spec['characteristic']
    mask = frame_ink(ink(document, chart['xref']))
    x = calibrate(rules(mask, 1, chart['coverage']), chart['x'])
    y = calibrate(rules(mask, 0, chart['coverage']), chart['y'])
    columns = readable(mask, x, y, chart['coverage'], chart['exclusions'])
    blue, green, red = track(columns, 3, chart['tolerance'])
    grid = np.arange(chart['x'][0], chart['x'][1] + chart['step'] / 2, chart['step'])
    return {name: rising(resample(curve, grid, chart['step'] / 2))
            for name, curve in (('red', red), ('green', green), ('blue', blue))}


def raster_mtf(document, spec):
    """The three layers' modulation transfer. A sample beyond the drawn span
    holds that curve's own endpoint, as the vector branch does."""
    import numpy as np
    chart = spec['mtf']
    mask = frame_ink(ink(document, chart['xref']))
    x = calibrate(rules(mask, 1, chart['coverage']), chart['x'], log=True)
    y = calibrate(rules(mask, 0, chart['coverage']), chart['y'], log=True)
    columns = readable(mask, x, y, chart['coverage'], chart['exclusions'])
    blue, green, red = track(columns, 3, chart['tolerance'])
    return [[n] + [float(np.interp(n, curve[:, 0], curve[:, 1])) / 100 for curve in (red, green, blue)]
            for n in MTF_SAMPLES]


def main():
    stock, arguments = (sys.argv[1] if len(sys.argv) > 1 else None), sys.argv[2:]
    if stock not in STOCKS:
        raise SystemExit(__doc__)
    spec = STOCKS[stock]
    borrows = spec.get('borrows')
    if len(arguments) != (5 if borrows else 4):
        raise SystemExit(__doc__)
    pdf, xyz_path, d65_path, output = arguments[0], *arguments[-3:]
    document = open_pinned(stock, pdf)
    out = pathlib.Path(output)
    out.mkdir(parents=True, exist_ok=True)

    def write(name, source, header, rows, source_spec=None):
        source_spec = source_spec or spec
        with (out / name).open('w') as handle:
            handle.write('# %s, %s; %s digitisation. See SOURCES.md.\n'
                         % (source_spec['publication'], source,
                            'vector-path' if source_spec['kind'] == 'vector' else 'raster-plate'))
            writer = csv.writer(handle, lineterminator='\n')
            writer.writerow(header)
            writer.writerows([[('%.6f' % v) if isinstance(v, float) else v for v in row] for row in rows])

    def write_spectral(source_document, source_spec):
        """The two charts a Stock may take from a sibling rather than its own sheet."""
        write('sensitivity.csv', 'page %d Spectral Sensitivity Curves' % source_spec['sensitivity']['page'],
              ['wavelengthNM', 'red', 'green', 'blue'], vector_sensitivity(source_document, source_spec), source_spec)
        write('dye-density.csv', 'page %d Spectral Dye Density Curves' % source_spec['dye']['page'],
              ['wavelengthNM', 'minimum', 'midscale'], vector_dye(source_document, source_spec), source_spec)

    if spec['kind'] == 'vector':
        page = spec['characteristic']['page']
        for name, rows in vector_characteristic(document, spec).items():
            write('neutral.%s.csv' % name, 'page %d Characteristic Curves' % page, ['logExposure', 'density'], rows)
        write_spectral(document, spec)
        write('mtf.csv', 'page %d Modulation-Transfer Function Curves' % spec['mtf']['page'],
              ['cyclesPerMM', 'red', 'green', 'blue'], vector_mtf(document, spec))
        if 'isolatedDye' in spec:
            write('isolated-dye-density.csv', 'page %d peak-normalized CMY Dye Density Curves' % spec['isolatedDye']['page'],
                  ['wavelengthNM', 'cyan', 'magenta', 'yellow'], vector_isolated_dye(document, spec))
        if 'granularity' in spec:
            write('granularity.csv', 'page %d Diffuse rms Granularity nomograph; absolute density, sigma-D at 48 um' % spec['granularity']['page'],
                  ['density', 'red', 'green', 'blue'], vector_granularity(document, spec))
    else:
        page = spec['characteristic']['page']
        for name, rows in raster_characteristic(document, spec).items():
            write('neutral.%s.csv' % name, 'page %d Sensitometric Curves' % page, ['logExposure', 'density'], rows)
        write('mtf.csv', 'page %d Modulation-Transfer Function Curves' % spec['mtf']['page'],
              ['cyclesPerMM', 'red', 'green', 'blue'], raster_mtf(document, spec))
        write_spectral(open_pinned(borrows, arguments[1]), STOCKS[borrows])

    xyz = {int(r[0]): list(map(float, r[1:])) for r in csv.reader(open(xyz_path))}
    d65 = {int(r[0]): float(r[1]) for r in csv.reader(open(d65_path))}
    with (out / 'observer.csv').open('w') as handle:
        handle.write('# CIE 1931 2 degree observer and D65, sampled at 10 nm; see SOURCES.md.\n')
        writer = csv.writer(handle, lineterminator='\n')
        writer.writerow(['wavelengthNM', 'x', 'y', 'z', 'illuminant'])
        for nm in WAVELENGTHS:
            writer.writerow([nm] + xyz[nm] + [d65[nm]])


if __name__ == '__main__':
    main()
