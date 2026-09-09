#!/usr/bin/env python3
"""Reproduce Kodak/CIE CSV digitisation for Portra 160. Requires PyMuPDF 1.28.2.
Usage: digitize-portra-160.py E4051.pdf CIE_xyz_1931_2deg.csv CIE_std_illum_D65.csv output-directory
No simulation/reference-project data is used.

Axis calibration comes from each chart's drawn plot box rather than hand-measured
grid lines, and is checked against the printed tick labels before anything is
written. Channel assignment comes from the vertical order of the chart's own
R/G/B and layer labels, not from drawing order.
"""
import pymupdf as f
import math
import csv
import pathlib
import hashlib
import sys

pdf, xyz_path, d65_path, output = sys.argv[1:]
if hashlib.sha256(pathlib.Path(pdf).read_bytes()).hexdigest() != 'a635048fc5e578747868684ff5a98fa2a6582a5d4542dd4ba2e132bc06d951c0':
    raise SystemExit('Expected Kodak E-4051 revised 2-16; PDF paths differ between editions')
p = f.open(pdf)[3]
ds = p.get_drawings()
out = pathlib.Path(output)
out.mkdir(parents=True, exist_ok=True)
# Plot box, axis extremes and curve groups per chart. The boxes are stroked
# rectangles; the extremes are the outermost printed tick labels on each axis.
CHARTS = {
 'characteristic': (25, (-4.0, 1.0), (4.0, 0.0), (33, 34, 35)),
 'sensitivity':    (49, (250.0, 750.0), (3.0, -1.0), (50, 51, 52)),
 'dye':            (62, (400.0, 700.0), (2.5, 0.0), (65, 66)),
 'mtf':            (108, (1.0, 600.0), (200.0, 1.0), (109, 110, 111)),
}
def box(name):
 r = ds[CHARTS[name][0]]['rect']
 return r.x0, r.y0, r.x1, r.y1
def axes(name):
 x0, y0, x1, y1 = box(name)
 (ax0, ax1), (ay0, ay1) = CHARTS[name][1], CHARTS[name][2]
 return (lambda x: ax0 + (x - x0) * (ax1 - ax0) / (x1 - x0),
         lambda y: ay0 + (y - y0) * (ay1 - ay0) / (y1 - y0))
def points(i):
 a=[]
 for item in ds[i]['items']:
  if item[0]=='l': a.extend([(q.x,q.y) for q in item[1:]])
  elif item[0]=='c':
   for j in range(101):
    t=j/100; q=item[1:]; w=[(1-t)**3,3*(1-t)**2*t,3*(1-t)*t*t,t**3]
    a.append(tuple(sum(w[k]*q[k][c] for k in range(4)) for c in range(2)))
 return sorted(set(a))
def y(i,x,zero=False):
 a=points(i)
 if x<a[0][0] or x>a[-1][0]: return None if zero else a[0 if x<a[0][0] else -1][1]
 for (u,v),(s,t) in zip(a,a[1:]):
  if u<=x<=s: return v+(t-v)*(x-u)/(s-u) if s>u else v
 return a[-1][1]
def labels():
 out=[]
 for b in p.get_text('dict')['blocks']:
  for line in b.get('lines',[]):
   for s in line['spans']:
    t=s['text'].strip()
    if t: out.append((t,(s['bbox'][0]+s['bbox'][2])/2,(s['bbox'][1]+s['bbox'][3])/2))
 return out
LABELS = labels()
def tick(text, anchor, axis):
 # The printed occurrence of a label nearest a point, reported on one axis.
 c = [l for l in LABELS if l[0] == text]
 if not c: raise SystemExit('Missing printed label ' + text)
 return min(c, key=lambda l: math.dist((l[1], l[2]), anchor))[1 + axis]
# A tick label is typeset beside its axis line, so it lands within a couple of
# points of it. A larger gap means the pinned plot box is not this chart's box.
for name, (_, (ax0, ax1), (ay0, ay1), _) in CHARTS.items():
 if name == 'mtf': continue  # logarithmic axes, checked separately below
 x0, y0, x1, y1 = box(name)
 for value, want, axis in [(ax0, x0, 0), (ax1, x1, 0), (ay0, y0, 1), (ay1, y1, 1)]:
  text = f'{value:.1f}' if name == 'characteristic' or axis == 1 else f'{value:.0f}'
  anchor = (want, y1 + 10) if axis == 0 else (x0 - 10, want)
  found = tick(text, anchor, axis)
  if abs(found - want) > 2.5:
   raise SystemExit(f'{name} axis label {text} is {abs(found - want):.2f} pt from the plot box')
def middle(name):
 x0, y0, x1, y1 = box(name)
 return ((x0 + x1) / 2, (y0 + y1) / 2)
def rank(name, at, letters):
 # Assign curves to channels by the vertical order of the chart's own labels.
 group = CHARTS[name][3]
 order = sorted(letters, key=lambda t: tick(t[0], middle(name), 1))
 return dict(zip([channel for _, channel in order], sorted(group, key=lambda i: y(i, at))))
def write(name,header,rows):
 with (out/name).open('w') as o:
  o.write('# Kodak E-4051, revised 2-16, page 4; vector-path digitisation. See SOURCES.md.\n')
  w=csv.writer(o,lineterminator='\n'); w.writerow(header)
  w.writerows([[f'{v:.6f}' if isinstance(v,float) else v for v in row] for row in rows])
# Characteristic Curves. The B/G/R labels sit at the low-exposure end of the
# curves they name, so the curves' order there is the labels' order.
cx, cy = axes('characteristic')
left = min(points(i)[0][0] for i in CHARTS['characteristic'][3])
channels = rank('characteristic', left, [('B', 'blue'), ('G', 'green'), ('R', 'red')])
# Portra 160's curves are drawn as Beziers rather than the polylines Portra 400
# uses, so there are no vertices to take. Sample each on a uniform 0.02
# log-exposure grid instead: a documented reduction, far finer than the printed
# grid and far coarser than the 0.02-density stroke width. Bezier sampling leaves
# dips of a few times 1e-5 density in the flattest part of the blue toe, which the
# Baker rejects as non-monotone. The blue toe also dips about 0.002 density just
# above its start. Take the running maximum, and refuse a correction approaching
# the printed stroke width, which would be a real feature rather than noise.
for c in ('red', 'green', 'blue'):
 a = points(channels[c])
 grid = [a[0][0] + i * 0.02 / abs(cx(1) - cx(0)) for i in range(int(abs(cx(a[-1][0]) - cx(a[0][0])) / 0.02) + 1)]
 rows, run, worst = [], None, 0.0
 for x in grid:
  d = cy(y(channels[c], x))
  if run is not None and d < run: worst, d = max(worst, run - d), run
  run = d
  rows.append((cx(x), d))
 if worst > 0.01: raise SystemExit(f'{c} curve falls by {worst:.6f} density; that is a feature, not stroke noise')
 write('neutral.'+c+'.csv',['logExposure','density'],rows)
# Spectral-Sensitivity Curves. Each layer's peak falls under its printed name,
# and the cyan-, magenta- and yellow-forming layers are the red, green and blue
# records. Outside a layer's drawn path, use zero: an assumption, not a
# measurement of the unplotted tail.
sx, sy = axes('sensitivity')
peaks = {i: min(points(i), key=lambda q: q[1])[0] for i in CHARTS['sensitivity'][3]}
layers = {'red': 'Cyan-', 'green': 'Magenta-', 'blue': 'Yellow-'}
named = {c: tick(layers[c], middle('sensitivity'), 0) for c in layers}
sens = {c: min(peaks, key=lambda i: abs(peaks[i] - named[c])) for c in layers}
if len(set(sens.values())) != 3: raise SystemExit('Ambiguous spectral-sensitivity layer assignment')
rows=[]
for nm in range(400,701,10):
 vals=[]
 for c in ('red','green','blue'):
  v=y(sens[c],(nm-250)*(box('sensitivity')[2]-box('sensitivity')[0])/500+box('sensitivity')[0],True)
  vals.append(0.0 if v is None else 10**sy(v))
 rows.append([nm]+vals)
write('sensitivity.csv',['wavelengthNM','red','green','blue'],rows)
# Spectral-Dye-Density Curves. Aggregate minimum and midscale neutral densities,
# not isolated cyan/magenta/yellow dye spectra. Midscale is the upper curve.
dx0, dy0, dx1, dy1 = box('dye')
_, dy = axes('dye')
mid, minimum = sorted(CHARTS['dye'][3], key=lambda i: min(q[1] for q in points(i)))
write('dye-density.csv',['wavelengthNM','minimum','midscale'],
      [[nm]+[dy(y(i,dx0+(nm-400)*(dx1-dx0)/300)) for i in (minimum,mid)] for nm in range(400,701,10)])
# Modulation Transfer Function, logarithmic on both axes. The R/G/B labels sit
# at the high-frequency end. Responses are stored as ratios, not percent. The
# drawn curves stop just short of 80 cycles/mm, so the grid stops at 70.
mx0, my0, mx1, my1 = box('mtf')
right = max(points(i)[-1][0] for i in CHARTS['mtf'][3])
mtf = rank('mtf', right, [('R', 'red'), ('G', 'green'), ('B', 'blue')])
def freq_x(n): return mx0 + math.log10(n) * (mx1 - mx0) / math.log10(600.0)
def response(v): return 10 ** (math.log10(200.0) + (v - my0) * (0 - math.log10(200.0)) / (my1 - my0)) / 100.0
write('mtf.csv',['cyclesPerMM','red','green','blue'],
      [[n]+[response(y(mtf[c],freq_x(n))) for c in ('red','green','blue')] for n in [3,5,10,20,30,40,50,60,70]])
xyz={int(r[0]):list(map(float,r[1:])) for r in csv.reader(open(xyz_path))}
d65={int(r[0]):float(r[1]) for r in csv.reader(open(d65_path))}
with (out/'observer.csv').open('w') as o:
 o.write('# CIE 1931 2 degree observer and D65, sampled at 10 nm; see SOURCES.md.\n')
 w=csv.writer(o,lineterminator='\n'); w.writerow(['wavelengthNM','x','y','z','illuminant'])
 for nm in range(400,701,10): w.writerow([nm]+xyz[nm]+[d65[nm]])
# Page 3, Print Grain Index, the 135-format table. Kodak says PGI replaces RMS
# granularity and cannot be compared to it, so no RMS is transcribed here.
write('print-grain-index.csv',['format','printWidthInches','printHeightInches','magnification','printGrainIndex'],
      [[135,4,6,4.4,28],[135,8,10,8.8,50],[135,16,20,17.8,79]])
