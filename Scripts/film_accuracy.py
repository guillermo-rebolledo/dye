#!/usr/bin/env python3
"""Score independent film-reference patch measurements, never self-generated goldens.

Usage: python3 Scripts/film_accuracy.py <manifest.json> <report.json>
Lab values must already use the manifest's fixed colour transform/reference white.
Density values must share the manifest's density status and measurement geometry.
"""

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import statistics


def delta_e_2000(reference, candidate):
    """CIEDE2000, parametric factors kL=kC=kH=1.

    Formula reference and independent test data: Sharma, Wu & Dalal (2005),
    https://hajim.rochester.edu/ece/sites/gsharma/ciede2000/
    This implementation is independent of their MATLAB implementation.
    """
    l1, a1, b1 = reference
    l2, a2, b2 = candidate
    c1, c2 = math.hypot(a1, b1), math.hypot(a2, b2)
    cbar = (c1 + c2) / 2
    g = .5 * (1 - math.sqrt(cbar**7 / (cbar**7 + 25**7)))
    a1, a2 = (1 + g) * a1, (1 + g) * a2
    c1, c2 = math.hypot(a1, b1), math.hypot(a2, b2)
    h1 = math.degrees(math.atan2(b1, a1)) % 360 if c1 else 0
    h2 = math.degrees(math.atan2(b2, a2)) % 360 if c2 else 0
    dl, dc = l2 - l1, c2 - c1
    dh = h2 - h1
    if c1 * c2 == 0:
        dh = 0
    elif dh > 180:
        dh -= 360
    elif dh < -180:
        dh += 360
    d_h = 2 * math.sqrt(c1 * c2) * math.sin(math.radians(dh / 2))
    lbar, cbar = (l1 + l2) / 2, (c1 + c2) / 2
    if c1 * c2 == 0:
        hbar = h1 + h2
    elif abs(h1 - h2) <= 180:
        hbar = (h1 + h2) / 2
    elif h1 + h2 < 360:
        hbar = (h1 + h2 + 360) / 2
    else:
        hbar = (h1 + h2 - 360) / 2
    cos = lambda degrees: math.cos(math.radians(degrees))
    t = 1 - .17 * cos(hbar - 30) + .24 * cos(2 * hbar) + .32 * cos(3 * hbar + 6) - .20 * cos(4 * hbar - 63)
    sl = 1 + .015 * (lbar - 50)**2 / math.sqrt(20 + (lbar - 50)**2)
    sc, sh = 1 + .045 * cbar, 1 + .015 * cbar * t
    rt = -2 * math.sqrt(cbar**7 / (cbar**7 + 25**7)) * math.sin(math.radians(60 * math.exp(-((hbar - 275) / 25)**2)))
    dl, dc, d_h = dl / sl, dc / sc, d_h / sh
    return math.sqrt(max(0, dl**2 + dc**2 + d_h**2 + rt * dc * d_h))


def required_text(document, key):
    value = document.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f'{key}: a nonempty recorded value is required')
    return value


def measurement_file(root, entry, columns):
    path = (root / required_text(entry, 'path')).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError('measurement paths must stay within the manifest directory')
    contents = path.read_bytes()
    if hashlib.sha256(contents).hexdigest() != required_text(entry, 'sha256'):
        raise ValueError(f'{path.name}: source hash mismatch')
    rows = csv.DictReader(contents.decode('utf-8').splitlines())
    if rows.fieldnames != ['sample', *columns]:
        raise ValueError(f'{path.name}: expected sample,{",".join(columns)}')
    result = {}
    for row in rows:
        name = row['sample']
        if not name or name in result or None in row:
            raise ValueError(f'{path.name}: duplicate/missing sample or extra column')
        values = tuple(float(row[key]) for key in columns)
        if not all(math.isfinite(value) and abs(value) <= 1e4 for value in values):
            raise ValueError(f'{path.name}: invalid measurement')
        result[name] = values
    if not result:
        raise ValueError(f'{path.name}: no measurements')
    return result


def summarize(values):
    values = sorted(values)
    # Nearest rank, documented to avoid changing conventions between reports.
    return {'count': len(values), 'median': statistics.median(values),
            'p95': values[math.ceil(.95 * len(values)) - 1], 'maximum': values[-1]}


def score(manifest_path):
    manifest_path = Path(manifest_path)
    manifest = json.loads(manifest_path.read_text())
    if manifest.get('schemaVersion') != 1:
        raise ValueError('unsupported manifest version')
    for key in ['referenceWorkflow', 'inputTransform', 'outputTransform', 'referenceWhite', 'usageRights']:
        required_text(manifest, key)
    cases = manifest.get('captures')
    if not isinstance(cases, list) or not cases:
        raise ValueError('No independent film captures: photographic accuracy has not been measured')
    rolls, scenes, ids, results = {}, {}, set(), []
    for capture in cases:
        for key in ['id', 'stock', 'batch', 'roll', 'scene', 'process', 'illuminant', 'exposure', 'scanner', 'inputKind']:
            required_text(capture, key)
        if capture['inputKind'] not in ['scene-linear-raw', 'rendered-photo']:
            raise ValueError('inputKind must distinguish scene-linear RAW from rendered photographs')
        if capture['id'] in ids:
            raise ValueError('duplicate capture ID')
        ids.add(capture['id'])
        split = capture.get('split')
        if split not in ['calibration', 'validation']:
            raise ValueError('split must be calibration or validation')
        for mapping, key in [(rolls, 'roll'), (scenes, 'scene')]:
            group = capture[key]
            if mapping.setdefault(group, split) != split:
                raise ValueError(f'{key} {group}: calibration/validation leakage')
        metric = capture.get('metric')
        if metric == 'deltaE00':
            columns = ['L', 'a', 'b']
        elif metric == 'density':
            columns = ['red', 'green', 'blue']
            required_text(capture, 'densityStatus')
            required_text(capture, 'measurementGeometry')
        else:
            raise ValueError('metric must be deltaE00 or density; do not conflate their units')
        reference = measurement_file(manifest_path.parent, capture['reference'], columns)
        candidate = measurement_file(manifest_path.parent, capture['candidate'], columns)
        if reference.keys() != candidate.keys():
            raise ValueError('reference and candidate sample IDs must match exactly')
        errors = {key: delta_e_2000(value, candidate[key]) if metric == 'deltaE00'
                  else max(abs(a - b) for a, b in zip(value, candidate[key])) for key, value in reference.items()}
        results.append({'id': capture['id'], 'stock': capture['stock'], 'split': split,
                        'illuminant': capture['illuminant'], 'exposure': capture['exposure'],
                        'inputKind': capture['inputKind'], 'metric': metric,
                        'summary': summarize(errors.values()), 'samples': errors})
    if 'validation' not in rolls.values():
        raise ValueError('a held-out validation roll is required; fitting error is not validation')
    # No invented pass threshold: reference repeatability must establish one.
    return {'schemaVersion': 1, 'manifestSHA256': hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
            'status': 'measured-no-acceptance-threshold',
            'referenceWorkflow': manifest['referenceWorkflow'], 'captures': results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('report', type=Path)
    args = parser.parse_args()
    try:
        report = score(args.manifest)
    except (ValueError, KeyError, TypeError, OSError) as error:
        parser.exit(2, f'Film accuracy: {error}\n')
    args.report.write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')


if __name__ == '__main__':
    main()
