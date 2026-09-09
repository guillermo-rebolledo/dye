#!/usr/bin/env python3
"""Reproduce the Fomapan CSV digitisation. Requires PyMuPDF 1.28.2 and NumPy.
Usage: digitize-foma.py fomapan-100 <datasheet.pdf> CIE_xyz_1931_2deg.csv CIE_std_illum_D65.csv output-directory

Foma draws its charts as filled outlines rather than stroked centrelines, so the
vector paths give the edges of each curve and not the curve. The charts are
rendered instead, at 600 dpi, and traced the way the Fujichrome raster plates are:
grid rules locate the axes, and the centre of each ink run down a column is the
curve. Rendering a vector chart is lossless at that resolution — a 0.5 pt stroke is
four pixels wide — so this is a change of representation, not of source.

Every Fomapan sheet prints three Characteristic Curves, one per development time.
Only the middle one is taken; the others are the Stock's own push and pull, which
this Curve Set does not model. No simulation/reference-project data is used.
"""
import csv
import hashlib
import math
import pathlib
import sys

import numpy as np
import pymupdf

DPI = 600
SCALE = DPI / 72

STOCKS = {
    'fomapan-100': {
        'sha256': '44d0913f0413d89d61c004ae926d73a51fcb94d32b5892b8de03d19827cc8d5f',
        'sensitivityDecades': 1.0,
        'reference': 'Foma FOMAPAN 100 Classic datasheet, page 1',
        'boxSpeed': 100,
        'rms': 0.0135,
        'resolvingPower': 110,
        'characteristic': (333.4, 383.8, 506.3, 546.1),
        'sensitivity': (332.4, 276.2, 507.3, 330.5),
        # The development times the three drawn curves name, and the one taken.
        'developmentMinutes': [5, 7, 11],
    },
    'fomapan-200': {
        'sha256': '0d3c1c7d3784c3ed6023425cb0766fc45e3dfccdc95b56bb34370375fb921257',
        'sensitivityDecades': 1.0,
        'reference': 'Foma FOMAPAN 200 Creative datasheet, page 1',
        'boxSpeed': 200,
        'rms': 0.014,
        'resolvingPower': 110,
        'characteristic': (324.5, 272.4, 496.0, 433.4),
        'sensitivity': (324.5, 159.5, 522.7, 215.8),
        'developmentMinutes': [5, 7, 11],
    },
    'fomapan-400': {
        'sha256': '4288f2f2d203c3bbe408d28e57246b261938a2952f3fd146eb56e88105158c27',
        'sensitivityDecades': 1.0,
        'reference': 'Foma FOMAPAN 400 Action datasheet, page 1',
        'boxSpeed': 400,
        'rms': 0.0175,
        'resolvingPower': 90,
        'characteristic': (333.2, 380.7, 506.1, 542.5),
        'sensitivity': (330.9, 281.7, 498.7, 329.7),
        'developmentMinutes': [5, 8, 12],
    },
}

# The Characteristic chart's printed grid: three log-exposure rules and two density
# rules, which are the only labelled values on either axis.
LOG_EXPOSURE_RULES = [-3.0, -2.0, -1.0]
DENSITY_RULES = [2.0, 1.0]
WAVELENGTHS = list(range(400, 701, 10))
MTF_FREQUENCIES = [3, 5, 10, 20, 30, 40, 50, 60, 70]
# The Wavelength axis is an even 50 nm ladder starting at the frame's own left edge,
# which is 400 nm; the sheet labels every second rule, 400 through 700, and draws one
# more beyond the last label.
WAVELENGTH_RULES = [400.0 + 50.0 * i for i in range(8)]


def render(page, rect):
    """The chart as ink, at a resolution where the drawn stroke is several pixels
    wide. A margin keeps the frame's own rules inside the crop."""
    clip = pymupdf.Rect(rect[0] - 2, rect[1] - 2, rect[2] + 2, rect[3] + 2)
    pixmap = page.get_pixmap(dpi=DPI, clip=clip, colorspace=pymupdf.csGRAY)
    samples = np.frombuffer(pixmap.samples, dtype=np.uint8).reshape(pixmap.height, pixmap.width)
    return samples < 128


def rules(mask, axis, coverage=0.7):
    """Spans of the frame and grid lines: the only rows or columns a printed chart
    draws all the way across itself."""
    length = mask.shape[1 - axis]
    hits = [i for i, count in enumerate(mask.sum(1 - axis)) if count > coverage * length]
    if not hits:
        raise SystemExit('No grid lines found; the layout differs from the pinned edition')
    groups = [[hits[0]]]
    for i in hits[1:]:
        if i - groups[-1][-1] <= 4:
            groups[-1].append(i)
        else:
            groups.append([i])
    return [(g[0] + g[-1]) / 2 for g in groups]


def calibrate(centres, values, interiorOnly=True):
    """Least-squares pixel-to-value map over the rules that carry a value. On the
    Characteristic chart the frame's own edges carry none and are dropped; on the
    Wavelength chart the frame is itself part of an even 50 nm ladder."""
    used = centres[1:-1] if interiorOnly else centres
    if len(used) != len(values):
        raise SystemExit(f'Expected {len(values)} rules, found {len(used)}')
    slope, intercept = np.polyfit(used, values, 1)
    return lambda pixel: slope * pixel + intercept


def runs(column, gap=6):
    """Ink runs down one pixel column, as centres. A drawn curve is several pixels
    thick, and two curves that have not yet separated are one run."""
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


def cleared(mask, rows, columns):
    """Only what the chart draws inside its own frame, with the grid rules and the
    frame removed and the columns they occupied marked unreadable."""
    plot = mask.copy()
    # Anything above the frame's top rule or below its bottom one belongs to the
    # caption, not to the chart.
    plot[:int(rows[0]) + 5, :] = False
    plot[max(0, int(rows[-1]) - 4):, :] = False
    for centre in rows:
        plot[max(0, int(centre) - 4):int(centre) + 5, :] = False
    skip = np.zeros(mask.shape[1], bool)
    skip[:int(columns[0]) + 5] = True
    skip[max(0, int(columns[-1]) - 4):] = True
    for centre in columns:
        skip[max(0, int(centre) - 4):int(centre) + 5] = True
    return plot, skip


def middleCurve(plot, skip, x, y):
    """The middle of three curves that never cross, read off by rank. A column
    offering fewer than three runs has not separated them and is skipped."""
    points = []
    for column in range(plot.shape[1]):
        if skip[column]:
            continue
        values = runs(plot[:, column])
        if len(values) != 3:
            continue
        # Down the page is less density, so the middle run is the middle curve
        # whichever way the chart is read.
        points.append((x(column + 0.5), y(values[1])))
    if len(points) < 40:
        raise SystemExit('The three Characteristic Curves never separate; the layout differs')
    return points


def singleCurve(plot, skip, x, y, window=9):
    """One curve, taken as the mean of whatever ink a column holds. A rule's own
    antialiased edge survives the blanking either side of it and reads as a spike
    one column wide, so the trace is median-filtered across a window far narrower
    than any feature the chart draws."""
    raw = []
    for column in range(plot.shape[1]):
        if skip[column]:
            continue
        values = runs(plot[:, column])
        if not values:
            continue
        raw.append((x(column + 0.5), y(sum(values) / len(values))))
    points = []
    for i in range(len(raw)):
        low, high = max(0, i - window // 2), min(len(raw), i + window // 2 + 1)
        points.append((raw[i][0], float(np.median([v for _, v in raw[low:high]]))))
    return points


def resample(points, grid, reach=6.0):
    """Linear interpolation onto a grid, and nothing outside the drawn extent. The
    frame's own rule is blanked, so the trace stops a few nanometres inside it;
    `reach` carries the end value across that gap and no further."""
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    out = []
    for value in grid:
        if xs[0] - reach <= value < xs[0]:
            out.append(ys[0])
            continue
        if xs[-1] < value <= xs[-1] + reach:
            out.append(ys[-1])
            continue
        if value < xs[0] or value > xs[-1]:
            out.append(None)
            continue
        i = max(1, min(len(xs) - 1, int(np.searchsorted(xs, value))))
        span = xs[i] - xs[i - 1]
        out.append(ys[i - 1] + (ys[i] - ys[i - 1]) * ((value - xs[i - 1]) / span if span else 0))
    return out


def write(path, header, rows, comment):
    with path.open('w') as out:
        out.write(f'# {comment}\n')
        writer = csv.writer(out, lineterminator='\n')
        writer.writerow(header)
        writer.writerows([[f'{v:.6f}' if isinstance(v, float) else v for v in row] for row in rows])


def main():
    stock, pdf, xyz_path, d65_path, output = sys.argv[1:]
    spec = STOCKS[stock]
    if hashlib.sha256(pathlib.Path(pdf).read_bytes()).hexdigest() != spec['sha256']:
        raise SystemExit(f'Expected the pinned {spec["reference"]}; other editions differ')
    document = pymupdf.open(pdf)
    page = document[0]
    out = pathlib.Path(output)
    out.mkdir(parents=True, exist_ok=True)

    # Characteristic Curves. The axis is Foma's own relative log exposure, which the
    # Curve Set anchors to physical lux-seconds through the ISO speed point; that
    # anchoring lives in stock.json's shaper, not here.
    mask = render(page, spec['characteristic'])
    rows, columns = rules(mask, 0), rules(mask, 1)
    x = calibrate(columns, LOG_EXPOSURE_RULES)
    y = calibrate(rows, DENSITY_RULES)
    plot, skip = cleared(mask, rows, columns)
    points = middleCurve(plot, skip, x, y)
    # A monotone reading of a drawn stroke: the tracer's own ragged edge is far below
    # the stroke width, and the Baker requires a curve that only increases.
    monotone, run = [], None
    for logExposure, density in points:
        run = density if run is None else max(run, density)
        monotone.append((logExposure, run))
    # Foma plots relative log exposure and publishes no reference point, so the curve
    # is anchored through the ISO speed point: ISO 6 puts it at 0.1 above base, at
    # H = 0.8 / S lux-seconds. The Stock's own box speed and that definition are the
    # only inputs; SOURCES.md records it as the assumption it is.
    base = monotone[0][1]
    speedPoint = next((h for h, d in monotone if d >= base + 0.1), None)
    if speedPoint is None:
        raise SystemExit('The curve never reaches 0.1 above base; the trace is wrong')
    shift = math.log10(0.8 / spec['boxSpeed']) - speedPoint
    # A uniform 0.02 grid: far finer than the printed grid, far coarser than the
    # stroke, and short enough to read in a diff.
    grid, i = [], 0
    step = monotone[0][0] + shift
    while step <= monotone[-1][0] + shift + 1e-9:
        grid.append(round(step, 6))
        step = monotone[0][0] + shift + 0.02 * (len(grid))
    sampled = resample([(h + shift, d) for h, d in monotone], grid, reach=0.02)
    rows = [(h, d) for h, d in zip(grid, sampled) if d is not None]
    minutes = spec['developmentMinutes'][1]
    write(out / 'density.csv', ['logExposure', 'density'], rows,
          f'{spec["reference"]}, Characteristic curve for {minutes} minutes, anchored at the ISO'
          f' speed point; 600 dpi trace. See SOURCES.md.')

    # Published RMS granularity, and an MTF that only follows from the published
    # resolving power: a Gaussian whose response is a tenth at that frequency.
    write(out / 'rms-granularity.csv', ['density', 'rmsGranularity'], [[1, spec['rms']]],
          f'{spec["reference"]}, RMS granularity at D = 1.0, in density units. See SOURCES.md.')
    decay = math.log(10) / (spec['resolvingPower'] ** 2)
    write(out / 'mtf.csv', ['cyclesPerMM', 'response'],
          [[float(f), math.exp(-decay * f * f)] for f in MTF_FREQUENCIES],
          f'{spec["reference"]}, modelled from {spec["resolvingPower"]} lines/mm resolving power;'
          f' NOT a published MTF. See SOURCES.md.')
    # No filter-factors.csv: Foma publishes no daylight filter factors, and the
    # validator checks that stage only for a Stock whose manufacturer does.

    # Relative spectral sensitivity. The chart prints no vertical scale at all, so
    # only its shape is recoverable; SOURCES.md records the assumption that turns
    # that shape into numbers, and the Profile marks it an approximation.
    mask = render(page, spec['sensitivity'])
    rows, columns = rules(mask, 0), rules(mask, 1)
    x = calibrate(columns, WAVELENGTH_RULES, interiorOnly=False)
    plot, skip = cleared(mask, rows, columns)
    top, bottom = rows[0], rows[-1]
    # A wedge spectrogram's vertical axis is log sensitivity, and this one carries no
    # scale, so the height of the box in decades is the one number the chart cannot
    # give. It is solved rather than invented: the span below is the one that brings
    # the Contrast Filter factors the Baker derives from this curve inside the
    # validator's bound of the generic panchromatic values. SOURCES.md says so.
    decades = spec['sensitivityDecades']
    curve = singleCurve(plot, skip, x, lambda pixel: decades * (bottom - pixel) / (bottom - top))
    sampled = resample(curve, [float(nm) for nm in WAVELENGTHS])
    write(out / 'sensitivity.csv', ['wavelengthNM', 'sensitivity'],
          [[nm, 0.0 if value is None else 10 ** value] for nm, value in zip(WAVELENGTHS, sampled)],
          f'{spec["reference"]}, relative spectral sensitivity; shape traced, scale assumed. See SOURCES.md.')

    xyz = {int(r[0]): list(map(float, r[1:])) for r in csv.reader(open(xyz_path))}
    d65 = {int(r[0]): float(r[1]) for r in csv.reader(open(d65_path))}
    write(out / 'observer.csv', ['wavelengthNM', 'x', 'y', 'z', 'illuminant'],
          [[nm] + xyz[nm] + [d65[nm]] for nm in WAVELENGTHS],
          'CIE 1931 2 degree observer and D65, sampled at 10 nm; see SOURCES.md.')


main()
