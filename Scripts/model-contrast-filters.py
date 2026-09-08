#!/usr/bin/env python3
"""Emit the shared Contrast Filter transmittance table. Pure Python, no inputs.
Usage: model-contrast-filters.py output-directory

The five filters are modelled as logistic band edges at the nominal Wratten
cut-on/cut-off wavelengths with a nominal peak transmittance. This is an
ARTISTIC model of coloured glass, not a digitised transmittance measurement;
see Curves/contrast-filters/SOURCES.md for what it is validated against.
"""
import csv
import pathlib
import sys

# (short-wavelength 50 % point nm, long-wavelength 50 % point nm, peak transmittance).
# A bound outside 400-700 nm means the filter does not close on that side inside
# the visible band the model integrates over.
FILTERS = {
    'yellow': (495.0, 780.0, 0.87),   # Wratten No. 8, minus-blue
    'orange': (520.0, 780.0, 0.88),   # Wratten No. 15, deep yellow/amber
    'red':    (595.0, 780.0, 0.90),   # Wratten No. 25, tricolour red
    'green':  (490.0, 600.0, 0.42),   # Wratten No. 58, tricolour green
    'blue':   (330.0, 495.0, 0.28),   # Wratten No. 47, tricolour blue
}
EDGE_NM = 7.0  # 10-90 % width of each edge, in nanometres


def edge(nm, centre):
 e = (centre - nm) / EDGE_NM
 return 0.0 if e > 30 else 1.0 if e < -30 else 1 / (1 + 10 ** e)


def transmittance(name, nm):
 low, high, peak = FILTERS[name]
 return peak * edge(nm, low) * (1 - edge(nm, high))


out = pathlib.Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
names = list(FILTERS)
with (out / 'transmittance.csv').open('w') as o:
 o.write('# Artistic logistic-edge model of five Kodak Wratten contrast filters. See SOURCES.md.\n')
 w = csv.writer(o, lineterminator='\n')
 w.writerow(['wavelengthNM'] + names)
 for nm in range(400, 701, 10):
  w.writerow([nm] + ['%.6f' % transmittance(n, nm) for n in names])
