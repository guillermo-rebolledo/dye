#!/usr/bin/env python3
"""Reproduce the Fujichrome/CIE CSV digitisation for PROVIA 100F and Velvia 50.
Requires PyMuPDF 1.28.2 and NumPy.
Usage: digitize-fujichrome.py provia-100f|velvia-50 <datasheet.pdf> <provia-datasheet.pdf> CIE_xyz_1931_2deg.csv CIE_std_illum_D65.csv output-directory

Unlike the Kodak datasheets, Fujifilm draws most of these charts as 1-bit raster
plates rather than vector paths, so the curves are recovered from ink pixels.
Provia's characteristic and dye-density charts are printed in colour and arrive
as one separation plate per curve, which separates them exactly; Velvia's are a
single black plate each, whose curves are told apart by line style or by their
own extent. No simulation/reference-project data is used.
"""
import csv
import hashlib
import math
import pathlib
import sys

import numpy as np
import pymupdf

STOCKS = {
    'provia-100f': {
        'sha256': 'e28d54e76e8fcdf44c8ffacc930b5b8f2ea54a7cdaeedfcc91790e68eb599de8',
        'reference': 'Fujifilm AF3-036E, page 5',
        'page': 5,
        'rms': 0.008,
    },
    'velvia-50': {
        'sha256': '668844e4cf81d5d234645c90d0b3217ed81c3be925a063b4752f7a71c3954d4c',
        'reference': 'Fujifilm AF3-0221E2, page 8',
        'page': 7,
        'rms': 0.009,
    },
}

# Both datasheets print the same response and frequency decades on the MTF chart.
MTF_RESPONSE_LABELS = [150, 100, 70, 50, 30, 20, 10, 7, 5, 3, 2]
MTF_FREQUENCY_LABELS = [1, 2, 5, 10, 20, 50, 100, 200]
MTF_SAMPLES = [3, 5, 10, 20, 30, 40, 50, 60]
WAVELENGTHS = list(range(400, 701, 10))


def ink(document, xref):
    """The plate's painted pixels. These are 1-bit image masks, so a sample is
    either ink or nothing; there is no antialiasing to threshold away."""
    pixmap = pymupdf.Pixmap(document, xref)
    return np.frombuffer(pixmap.samples, dtype=np.uint8).reshape(pixmap.height, pixmap.width) > 127


def rules(mask, axis, coverage=0.6):
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
    return [(g[0], g[-1]) for g in groups]


def centres(spans):
    return [(first + last) / 2 for first, last in spans]


def calibrate(centres, labels, log=False):
    """Least-squares pixel-to-value map. A grid line the curves or the caption
    box interrupt simply goes undetected, so each detected line is snapped to the
    nearest printed label rather than assumed to be the n-th of them."""
    values = [math.log10(v) for v in labels] if log else list(map(float, labels))
    span = (values[-1] - values[0]) / (centres[-1] - centres[0])
    snapped = [min(values, key=lambda v: abs(v - (values[0] + span * (c - centres[0])))) for c in centres]
    if len(set(snapped)) != len(snapped):
        raise SystemExit('Ambiguous axis calibration; the plate layout differs from the pinned edition')
    slope, intercept = np.polyfit(centres, snapped, 1)
    return lambda pixel: (lambda v: 10 ** v if log else v)(slope * pixel + intercept)


def runs(column, gap=4):
    """Ink runs down one pixel column, as centres. A drawn curve is several
    pixels thick, and two curves that have not yet separated are one run."""
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


def plot(mask, coverage=0.6):
    """Only what the chart draws inside its own frame: grid lines removed, the
    columns they occupied marked unreadable, and the axis labels around the
    frame discarded. Blanking a few pixels either side of a rule keeps its
    ragged edge out of the runs."""
    rows, columns = rules(mask, 0, coverage), rules(mask, 1, coverage)
    cleared = mask.copy()
    cleared[:rows[0][1] + 4, :] = False
    cleared[max(0, rows[-1][0] - 3):, :] = False
    for first, last in rows:
        cleared[max(0, first - 3):last + 4, :] = False
    skip = np.zeros(mask.shape[1], bool)
    skip[:columns[0][1] + 4] = True
    skip[max(0, columns[-1][0] - 3):] = True
    for first, last in columns:
        skip[max(0, first - 3):last + 4] = True
    return cleared, skip


def readable(mask, skip, x, y, exclusions):
    """Run centres in chart coordinates, top of the chart first, with the
    captions and legend keys the datasheet prints inside its own plot area
    removed by the rectangles the caller names."""
    out = {}
    for column in range(mask.shape[1]):
        if skip[column]:
            continue
        horizontal = x(column + 0.5)
        values = [y(centre) for centre in runs(mask[:, column])]
        values = [v for v in values
                  if not any(a <= horizontal <= b and c <= v <= d for a, b, c, d in exclusions)]
        if values:
            out[horizontal] = sorted(values, reverse=True)
    return out


def track(columns, count, tolerance):
    """Follow `count` curves across a chart that draws them in one colour, in
    both directions from the first column that separates them all. Each curve
    continues to the run nearest where it was; a column that offers nothing that
    near is left to the interpolation between the columns that do, which is how
    a dashed curve is read across its gaps and how a curve that has gone under
    another one comes back. Only for curves that never change places."""
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
                predicted = points[-1]
                nearest = min(columns[key], key=lambda v: abs(v - predicted))
                if abs(nearest - predicted) <= tolerance:
                    tracks[i][key] = nearest
                    points.append(nearest)
    return [np.array(sorted(t.items())) for t in tracks]


def chains(columns, minimum):
    """Split the run centres into curve segments without knowing how many the
    chart draws. A run continues the chain whose extrapolated position it is
    nearest; anything else starts one. Printed text inside the plot area falls
    out as chains shorter than `minimum` columns."""
    keys = sorted(columns)
    active, finished = [], []
    for key in keys:
        for value in columns[key]:
            best, distance = None, None
            for chain in active:
                (lastX, lastY) = chain[-1]
                slope = ((lastY - chain[-2][1]) / (lastX - chain[-2][0])) if len(chain) > 1 and chain[-2][0] < lastX else 0
                gap = abs(lastY + slope * (key - lastX) - value)
                if key - lastX < 12 and gap < 0.08 and (distance is None or gap < distance):
                    best, distance = chain, gap
            if best is None:
                active.append([(key, value)])
            else:
                best.append((key, value))
        for chain in list(active):
            if key - chain[-1][0] >= 12:
                active.remove(chain)
                finished.append(chain)
    return [np.array(c) for c in finished + active if len(c) >= minimum]


def sample(curve, at, clamp=True):
    """The curve at one coordinate, holding its endpoints unless the caller
    wants what the chart leaves undrawn reported as absent."""
    if not clamp and not curve[0][0] <= at <= curve[-1][0]:
        return None
    return float(np.interp(at, curve[:, 0], curve[:, 1]))


def bezier(items):
    """Vector path vertices, cubic segments resampled at 101 points, as the
    Kodak scripts do. Provia prints its spectral sensitivity as paths."""
    out = []
    for item in items:
        if item[0] == 'l':
            out.extend((p.x, p.y) for p in item[1:])
        elif item[0] == 'c':
            q = item[1:]
            for j in range(101):
                t = j / 100
                w = [(1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3]
                out.append(tuple(sum(w[k] * q[k][c] for k in range(4)) for c in range(2)))
    return np.array(sorted(set(out)))


def resample(points, grid, window):
    """A curve on `grid`, each sample the mean of the tracked points within
    `window` of it. A run centre wanders by a pixel or two as a printed stroke's
    edge frays, and reading one column per sample keeps that jitter — which is
    inside the stroke width, but is a corner the Colour Cube then has to follow
    and cannot. Averaging across the stroke's own width removes it."""
    curve = np.asarray(points)
    out = []
    for x in grid:
        near = curve[np.abs(curve[:, 0] - x) <= window]
        out.append((x, float(near[:, 1].mean()) if len(near) else sample(curve, x)))
    return out


def falling(points):
    """A reversal Stock's density only falls as exposure rises. A run centre
    wanders by a pixel where the printed stroke is flat, so hold it to that."""
    out = []
    for horizontal, density in points:
        out.append((horizontal, min(density, out[-1][1]) if out else density))
    return out


def characteristic(document, page, stock):
    """Density against log exposure, per layer. Reversal curves fall as exposure
    rises, and the three layers are printed on top of one another wherever the
    stock develops neutrally, so a layer is only drawn where it departs from the
    one covering it."""
    if stock == 'provia-100f':
        # One separation plate per curve, so no two curves are ever confused.
        black = ink(document, 50)
        x = calibrate(centres(rules(black, 1)), [-3.5 + 0.5 * i for i in range(10)])
        y = calibrate(centres(rules(black, 0, 0.35)), [4.0 - 0.5 * i for i in range(9)])
        curves = {}
        for name, xref in (('red', 52), ('green', 51), ('blue', 53)):
            plate = ink(document, xref)
            points = []
            for column in range(plate.shape[1]):
                for centre in runs(plate[:, column]):
                    horizontal, density = x(column + 0.5), y(centre)
                    # The legend keys are drawn inside the plot, below the curves.
                    if horizontal < -2.4 and density < 2.0:
                        continue
                    points.append((horizontal, density))
                    break
            curves[name] = np.array(points)
        red = curves['red']
        result = {}
        for name, curve in curves.items():
            end = curve[-1][0]
            offset = curve[-1][1] - sample(red, end)
            # Beyond where a layer stops being drawn it is under the layer that
            # covers it. Carry the junction's departure from that layer to zero
            # over a fifth of a decade rather than stepping to it.
            grid = np.arange(-3.40, 0.801, 0.05)
            joined = [(h, v) for h, v in curve if h <= end]
            joined += [(h, sample(red, h) + offset * max(0.0, 1 - (h - end) / 0.2))
                       for h in np.arange(end, 0.801, 0.005) if h > end]
            result[name] = falling(resample(joined, grid, 0.025))
        return result
    black = ink(document, 41)
    x = calibrate(centres(rules(black, 1)), [-3.0 + 0.5 * i for i in range(10)])
    y = calibrate(centres(rules(black, 0, 0.35)), [4.0 - 0.5 * i for i in range(9)])
    cleared, skip = plot(black, 0.35)
    columns = readable(cleared, skip, x, y, [(-3.0, -2.1, 0.02, 1.5),    # legend keys
                                             (-1.5, 1.5, 3.2, 4.0),      # exposure caption
                                             (-3.0, 1.5, 3.99, 4.0), (-3.0, 1.5, -1.0, 0.02)])
    # Velvia prints one black plate: green is dash-dot, blue dashed, red solid,
    # and above D-max they separate in that order. Where the chart draws one
    # line all three tracks land on it, which is what the chart is asserting.
    green, blue, red = track(columns, 3, 0.09)
    grid = np.arange(-2.85, 1.101, 0.05)
    result = {}
    for name, curve in (('red', red), ('green', green), ('blue', blue)):
        result[name] = falling(resample(curve, grid, 0.025))
    return result


def sensitivity(document, page, stock):
    """Log sensitivity against wavelength, converted to linear sensitivity.
    Outside a layer's drawn path the model uses zero, which is an assumption
    rather than a measurement of the unplotted tail."""
    if stock == 'provia-100f':
        drawings = page.get_drawings()
        frame = drawings[22]['rect']
        # The chart's own grid: 400 nm and 100 nm per division across, one log
        # unit per division down, read from the frame's drawn rules.
        horizontal = sorted(p[1].y for p in drawings[22]['items'][1:4])
        vertical = sorted(p[1].x for p in drawings[22]['items'][4:])
        x = calibrate(vertical, [400, 500, 600, 700])
        y = calibrate(horizontal, [1.0, 0.0, -1.0])
        curves = {name: np.array([(x(p[0]), y(p[1])) for p in bezier(drawings[i]['items'])])
                  for name, i in (('red', 23), ('green', 24), ('blue', 25))}
        rows = []
        for nm in WAVELENGTHS:
            row = [nm]
            for name in ('red', 'green', 'blue'):
                value = sample(curves[name], nm, clamp=False)
                row.append(0.0 if value is None else 10 ** value)
            rows.append(row)
        return rows
    black = ink(document, 42)
    x = calibrate(centres(rules(black, 1))[1:-1], [400, 500, 600, 700])
    y = calibrate(centres(rules(black, 0)), [2.0, 1.0, 0.0, -1.0])
    cleared, skip = plot(black)
    # The caption is the only thing outside the curves' own reach; the layer
    # labels are shorter than any curve and drop out of the chaining.
    columns = readable(cleared, skip, x, y, [(385, 720, 1.15, 2.0)])
    blue, green, red = sorted(sorted(chains(columns, 40), key=len)[-3:], key=lambda c: c[:, 0].mean())
    rows = []
    for nm in WAVELENGTHS:
        row = [nm]
        for curve in (red, green, blue):
            value = sample(curve, nm, clamp=False)
            row.append(0.0 if value is None else 10 ** value)
        rows.append(row)
    return rows


def dye_density(document):
    """Peak-normalised spectral diffuse density of the isolated cyan, magenta
    and yellow image dyes, from PROVIA 100F's four-plate colour chart. Both
    datasheets publish the separated dyes rather than the aggregate minimum and
    midscale neutral curves Kodak does, but only Provia's is printed in colour;
    Velvia's is one black plate of three curves that cross one another, and no
    separation of it is reliable enough to call a measurement. Velvia therefore
    borrows this one, which its Curve Set records as an approximation."""
    black = ink(document, 55)
    x = calibrate(centres(rules(black, 1))[1:-1], [400, 500, 600, 700])
    y = calibrate(centres(rules(black, 0))[1:], [1.0, 0.5, 0.0])
    curves = {}
    for name, xref in (('cyan', 58), ('magenta', 57), ('yellow', 56)):
        plate = ink(document, xref)
        points = [(x(column + 0.5), y(centre))
                  for column in range(plate.shape[1]) for centre in runs(plate[:, column])[:1]]
        curves[name] = np.array(points)
    rows = []
    for nm in WAVELENGTHS:
        rows.append([nm] + [max(0.0, sample(curves[name], nm)) for name in ('cyan', 'magenta', 'yellow')])
    peaks = [max(row[i] for row in rows) for i in (1, 2, 3)]
    # The chart is drawn peak-normalised; the extraction reproduces that exactly
    # rather than leaving a stroke-width scale error in the dye amplitudes.
    return [[row[0]] + [row[i + 1] / peaks[i] for i in range(3)] for row in rows]


def mtf(document, page, stock):
    """One published modulation transfer curve, on logarithmic axes. Fujifilm
    prints a single curve rather than one per layer; the same values fill the
    red, green and blue columns, which is a documented reduction rather than a
    claim of three measurements."""
    black = ink(document, 54 if stock == 'provia-100f' else 39)
    x = calibrate(centres(rules(black, 1)), MTF_FREQUENCY_LABELS, log=True)
    y = calibrate(centres(rules(black, 0)), MTF_RESPONSE_LABELS, log=True)
    cleared, skip = plot(black)
    columns = readable(cleared, skip, x, y, [(1, 200, 2, 4.2),        # exposure caption
                                             (1, 200, 145, 200)])
    curve = np.array(sorted((k, v[0]) for k, v in columns.items()))
    return [[n] + [sample(curve, n) / 100] * 3 for n in MTF_SAMPLES if curve[0][0] <= n <= curve[-1][0]]


def open_pinned(stock, path):
    if hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest() != STOCKS[stock]['sha256']:
        raise SystemExit('Unexpected %s datasheet edition; the plate layout differs between editions' % stock)
    return pymupdf.open(path)


def main():
    stock, pdf, provia_pdf, xyz_path, d65_path, output = sys.argv[1:]
    if stock not in STOCKS:
        raise SystemExit('Expected provia-100f or velvia-50')
    spec = STOCKS[stock]
    document = open_pinned(stock, pdf)
    provia = document if stock == 'provia-100f' else open_pinned('provia-100f', provia_pdf)
    page = document[spec['page']]
    out = pathlib.Path(output)
    out.mkdir(parents=True, exist_ok=True)

    def write(name, source, header, rows, reference=None):
        with (out / name).open('w') as handle:
            handle.write('# %s, %s; raster/vector digitisation. See SOURCES.md.\n'
                         % (reference or spec['reference'], source))
            writer = csv.writer(handle, lineterminator='\n')
            writer.writerow(header)
            writer.writerows([[('%.6f' % v) if isinstance(v, float) else v for v in row] for row in rows])

    for name, rows in characteristic(document, page, stock).items():
        write('neutral.%s.csv' % name, 'Characteristic Curves', ['logExposure', 'density'], rows)
    write('sensitivity.csv', 'Spectral Sensitivity Curves', ['wavelengthNM', 'red', 'green', 'blue'],
          sensitivity(document, page, stock))
    write('dye-density.csv', 'Spectral Dye Density Curves', ['wavelengthNM', 'cyan', 'magenta', 'yellow'],
          dye_density(provia), reference=STOCKS['provia-100f']['reference'])
    write('mtf.csv', 'MTF Curve', ['cyclesPerMM', 'red', 'green', 'blue'], mtf(document, page, stock))
    # Fujifilm publishes one diffuse RMS granularity value, read through the
    # standard 48 µm aperture at 1.0 above minimum density. Unlike Kodak's Print
    # Grain Index this is the measurement the Grain Pass wants.
    write('rms-granularity.csv', 'Diffuse RMS Granularity Value', ['density', 'rmsGranularity'],
          [[1.0, spec['rms']]])

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
