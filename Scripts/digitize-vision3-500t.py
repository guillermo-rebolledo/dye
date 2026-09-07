#!/usr/bin/env python3
"""Reproduce Kodak/CIE CSV digitisation for VISION3 500T. Requires PyMuPDF 1.28.2.
Usage: digitize-vision3-500t.py H-1-5219t.pdf CIE_xyz_1931_2deg.csv CIE_std_illum_D65.csv output-directory
No simulation/reference-project data is used.
"""
import pymupdf as f
import math
import csv
import pathlib
import hashlib
import sys

pdf, xyz_path, d65_path, output = sys.argv[1:]
if hashlib.sha256(pathlib.Path(pdf).read_bytes()).hexdigest() != '06eca2287fbaf57a1aeacbb8151bbd48e23aefb30af2114b412e9c1c63f4d1db':
    raise SystemExit('Expected Kodak H-1-5219t revised 7-15; PDF paths differ between editions')
doc = f.open(pdf)
out = pathlib.Path(output)
out.mkdir(parents=True, exist_ok=True)
drawings = {p: doc[p].get_drawings() for p in (2, 3, 4)}
def points(page, i):
 a=[]
 for item in drawings[page][i]['items']:
  if item[0]=='l': a.extend([(q.x,q.y) for q in item[1:]])
  elif item[0]=='c':
   for j in range(101):
    t=j/100; q=item[1:]; w=[(1-t)**3,3*(1-t)**2*t,3*(1-t)*t*t,t**3]
    a.append(tuple(sum(w[k]*q[k][c] for k in range(4)) for c in range(2)))
 return sorted(set(a))
def y(page,i,x,zero=False):
 a=points(page,i)
 if x<a[0][0] or x>a[-1][0]: return None if zero else a[0 if x<a[0][0] else -1][1]
 for (u,v),(s,t) in zip(a,a[1:]):
  if u<=x<=s: return v+(t-v)*(x-u)/(s-u) if s>u else v
 return a[-1][1]
def write(name,source,header,rows):
 with (out/name).open('w') as o:
  o.write('# Kodak H-1-5219t, revised 7-15, %s; vector-path digitisation. See SOURCES.md.\n' % source)
  w=csv.writer(o,lineterminator='\n'); w.writerow(header)
  w.writerows([[f'{v:.6f}' if isinstance(v,float) else v for v in row] for row in rows])
# Page 4 Characteristic Curves. Plot frame x 353.63...538.15 spans log H -4...1
# lux-seconds; y 306.79...122.30 spans Status M-style ECN-2 density 0...3.
# Bezier segments are resampled on a uniform 0.05 log-exposure grid.
for c,i in [('red',95),('green',93),('blue',94)]:
 a=[((x-353.63)/((538.15-353.63)/5)-4,(306.79-v)/((306.79-122.30)/3)) for x,v in points(3,i)]
 def at(x):
  for (u,p),(s,q) in zip(a,a[1:]):
   if u<=x<=s: return p+(q-p)*(x-u)/(s-u) if s>u else p
  return a[0][1] if x<a[0][0] else a[-1][1]
 write('neutral.'+c+'.csv','page 4 Characteristic Curves',['logExposure','density'],
       [(-4+k*0.05, at(-4+k*0.05)) for k in range(101)])
# Page 4 Spectral Sensitivity. x 250...750 nm over 353.30...553.80; log sensitivity
# 0.0 at y 669.78 with 37.855 points per decade. Cyan/magenta/yellow-forming layers
# record red/green/blue sensitivity; outside a drawn path the model uses zero.
rows=[]
for nm in range(400,701,10):
 vals=[]
 for i in [112,111,110]:
  v=y(3,i,353.30+(nm-250)*(553.80-353.30)/500,True)
  vals.append(0.0 if v is None else 10**((669.78-v)/37.855))
 rows.append([nm]+vals)
write('sensitivity.csv','page 4 Spectral Sensitivity Curves',['wavelengthNM','red','green','blue'],rows)
# Page 5 Spectral Dye Density. x 400...800 nm over 81.57...265.89; density 0 at
# y 321.52 with 92.26 points per unit. Aggregate minimum and midscale neutral only.
write('dye-density.csv','page 5 Spectral Dye Density Curves',['wavelengthNM','minimum','midscale'],
      [[nm]+[(321.52-y(4,i,81.57+(nm-400)*(265.89-81.57)/400))/92.26 for i in [32,31]] for nm in range(400,701,10)])
# Page 3 Modulation Transfer Function, logarithmic on both axes: 1 cycle/mm at
# x 362.59 with 72.90 points per decade; 1% response at y 489.82 with 66.49.
write('mtf.csv','page 3 Modulation-Transfer Function Curves',['cyclesPerMM','red','green','blue'],
      [[n]+[10**((489.82-y(2,i,362.59+math.log10(n)*72.90))/66.49)/100 for i in [44,45,46]] for n in [3,5,10,20,30,40,50,60,70,80]])
xyz={int(r[0]):list(map(float,r[1:])) for r in csv.reader(open(xyz_path))}
d65={int(r[0]):float(r[1]) for r in csv.reader(open(d65_path))}
with (out/'observer.csv').open('w') as o:
 o.write('# CIE 1931 2 degree observer and D65, sampled at 10 nm; see SOURCES.md.\n')
 w=csv.writer(o,lineterminator='\n'); w.writerow(['wavelengthNM','x','y','z','illuminant'])
 for nm in range(400,701,10): w.writerow([nm]+xyz[nm]+[d65[nm]])
