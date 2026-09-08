#!/usr/bin/env python3
"""Reproduce Kodak/CIE CSV digitisation for TRI-X 400. Requires PyMuPDF 1.28.2.
Usage: digitize-tri-x-400.py F-4017.pdf CIE_xyz_1931_2deg.csv CIE_std_illum_D65.csv output-directory
No simulation/reference-project data is used.
"""
import pymupdf as f
import math
import csv
import pathlib
import hashlib
import sys

pdf, xyz_path, d65_path, output = sys.argv[1:]
if hashlib.sha256(pathlib.Path(pdf).read_bytes()).hexdigest() != '51d738f4f996c98716d153bab75e41d0359637a18ea49f9be52062652b0b27d2':
    raise SystemExit('Expected Kodak F-4017 revised 2-16; PDF paths differ between editions')
doc = f.open(pdf)
out = pathlib.Path(output)
out.mkdir(parents=True, exist_ok=True)
drawings = {p: doc[p].get_drawings() for p in (6,)}
def points(page, i):
 a=[]
 for item in drawings[page][i]['items']:
  if item[0]=='l': a.extend([(q.x,q.y) for q in item[1:]])
  elif item[0]=='c':
   for j in range(101):
    t=j/100; q=item[1:]; w=[(1-t)**3,3*(1-t)**2*t,3*(1-t)*t*t,t**3]
    a.append(tuple(sum(w[k]*q[k][c] for k in range(4)) for c in range(2)))
 return sorted(set(a))
# Hold the first drawn value to the left of a path and return None to its right:
# a chart truncates the short-wavelength end of a spectral curve at its plotting
# limit, while the long-wavelength end leaves through the bottom of the chart.
def y(page,i,x):
 a=points(page,i)
 if x<a[0][0]: return a[0][1]
 if x>a[-1][0]: return None
 for (u,v),(s,t) in zip(a,a[1:]):
  if u<=x<=s: return v+(t-v)*(x-u)/(s-u) if s>u else v
 return a[-1][1]
# Log axes are calibrated by least squares over the chart's own printed tick labels.
def axis(page,x0,x1,y0,y1,horizontal):
 p=[]
 for w in doc[page].get_text('words'):
  if x0<=w[0]<=x1 and y0<=w[1]<=y1:
   try: v=float(w[4])
   except ValueError: continue
   p.append((math.log10(v),(w[0]+w[2])/2 if horizontal else (w[1]+w[3])/2))
 n=len(p); sx=sum(u for u,_ in p); sy=sum(v for _,v in p)
 sxx=sum(u*u for u,_ in p); sxy=sum(u*v for u,v in p)
 b=(n*sxy-sx*sy)/(n*sxx-sx*sx)
 return (sy-b*sx)/n, b
def write(name,header,rows,note):
 with (out/name).open('w') as o:
  o.write('# %s\n' % note)
  w=csv.writer(o,lineterminator='\n'); w.writerow(header)
  w.writerows([[f'{v:.6f}' if isinstance(v,float) else v for v in row] for row in rows])

# Page 7, Characteristic Curves, TRI-X 400 / 400TX 35 mm, T-MAX Developer, small tank,
# 20 C, 6 minutes: the solid curve, and the datasheet's own recommended normal time.
# Chart limits x = -4...1 log lux-seconds at 366.4...550.9, D = 4...0 at 69.5...254.0.
write('density.csv',['logExposure','density'],
      [((x-366.4)/((550.9-366.4)/5)-4,(254.0-v)/((254.0-69.5)/4)) for x,v in points(6,94)],
      'Kodak F-4017, revised 2-16, page 7; vector-path digitisation. See SOURCES.md.')

# Page 7, Spectral Sensitivity Curves, D = 0.3 above gross fog. Chart limits
# 250...750 nm at 86.9...287.4, log sensitivity 4...0 at 291.7...443.0.
rows=[]
for nm in range(400,701,10):
 v=y(6,69,86.9+(nm-250)*(287.4-86.9)/500)
 rows.append([nm, 0.0 if v is None else 10**((443.0-v)/((443.0-291.7)/4))])
write('sensitivity.csv',['wavelengthNM','sensitivity'],rows,
      'Kodak F-4017, revised 2-16, page 7; vector-path digitisation. See SOURCES.md.')

# Page 7, Modulation Transfer Function. Both axes are logarithmic; responses are
# stored as ratios rather than percent.
ax,bx=axis(6,80,295,233,243,True); ay,by=axis(6,60,82,70,235,False)
write('mtf.csv',['cyclesPerMM','response'],
      [[n,10**((y(6,33,ax+bx*math.log10(n))-ay)/by)/100] for n in [3,5,10,20,30,40,50,60,70]],
      'Kodak F-4017, revised 2-16, page 7; vector-path digitisation. See SOURCES.md.')

# Page 6, Image Structure: diffuse rms granularity 17, read at a net diffuse density
# of 1.0 through a 48 um aperture. Stored in density units.
write('rms-granularity.csv',['density','rmsGranularity'],[[1,0.017]],
      'Kodak F-4017, revised 2-16, page 6 table; transcribed. See SOURCES.md.')

# Page 1, Filter Corrections, TRI-X 400 / 400TX, daylight column. Wratten numbers
# map to the Contrast Filter names in Curves/contrast-filters.
write('filter-factors.csv',['filter','daylightFactor'],
      [['yellow',2.0],['orange',2.5],['red',8.0],['green',6.0],['blue',6.0]],
      'Kodak F-4017, revised 2-16, page 1 table; transcribed. See SOURCES.md.')

xyz={int(r[0]):list(map(float,r[1:])) for r in csv.reader(open(xyz_path))}
d65={int(r[0]):float(r[1]) for r in csv.reader(open(d65_path))}
with (out/'observer.csv').open('w') as o:
 o.write('# CIE 1931 2 degree observer and D65, sampled at 10 nm; see SOURCES.md.\n')
 w=csv.writer(o,lineterminator='\n'); w.writerow(['wavelengthNM','x','y','z','illuminant'])
 for nm in range(400,701,10): w.writerow([nm]+xyz[nm]+[d65[nm]])
