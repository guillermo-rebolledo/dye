#!/usr/bin/env python3
"""Reproduce Kodak/CIE CSV digitisation. Requires PyMuPDF 1.28.2.
Usage: digitize-portra.py E4050.pdf CIE_xyz_1931_2deg.csv CIE_std_illum_D65.csv output-directory
No simulation/reference-project data is used.
"""
import pymupdf as f
import math
import csv
import pathlib
import hashlib
import sys

pdf, xyz_path, d65_path, output = sys.argv[1:]
if hashlib.sha256(pathlib.Path(pdf).read_bytes()).hexdigest() != 'e83ac6775d37832a4cb466892a3e1cf4c88917a6ee93384e59d6924b1cd97e3a':
    raise SystemExit('Expected Kodak E-4050 revised 2-16; PDF paths differ between editions')
p = f.open(pdf)[3]
ds = p.get_drawings()
out = pathlib.Path(output)
out.mkdir(parents=True, exist_ok=True)
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
def write(name,header,rows):
 with (out/name).open('w') as o:
  o.write('# Kodak E-4050, revised 2-16, page 4; vector-path digitisation. See SOURCES.md.\n')
  w=csv.writer(o,lineterminator='\n'); w.writerow(header)
  w.writerows([[f'{v:.6f}' if isinstance(v,float) else v for v in row] for row in rows])
for c,i in [('red',38),('green',37),('blue',36)]:
 write('neutral.'+c+'.csv',['logExposure','density'],[((x-81.163)/((265.626-81.163)/5)-4,(287.368-v)/((287.368-102.853)/4)) for x,v in points(i)])
rows=[]
for nm in range(400,701,10):
 vals=[]
 for i in [54,55,53]:
  v=y(i,76.214+(nm-250)*(276.727-76.214)/500,True)
  vals.append(0.0 if v is None else 10**((494.555-v)/((494.555-343.059)/4)))
 rows.append([nm]+vals)
write('sensitivity.csv',['wavelengthNM','red','green','blue'],rows)
write('dye-density.csv',['wavelengthNM','minimum','midscale'],[[nm]+[(288.06-y(i,357.139+(nm-400)*(541.74-357.139)/300))/((288.06-103.714)/2.5) for i in [69,68]] for nm in range(400,701,10)])
# Logarithmic MTF axes, measured from PDF grid lines: x(1), x(100), y(100%), y(10%).
write('mtf.csv',['cyclesPerMM','red','green','blue'],[[n]+[10**((367.116974-y(i,348.429352+math.log10(n)*(494.715027-348.429352)/2))/(439.211426-367.116974)) for i in [116,115,114]] for n in [3,5,10,20,30,40,50,60,70,80]])
xyz={int(r[0]):list(map(float,r[1:])) for r in csv.reader(open(xyz_path))}
d65={int(r[0]):float(r[1]) for r in csv.reader(open(d65_path))}
with (out/'observer.csv').open('w') as o:
 o.write('# CIE 1931 2 degree observer and D65, sampled at 10 nm; see SOURCES.md.\n')
 w=csv.writer(o,lineterminator='\n'); w.writerow(['wavelengthNM','x','y','z','illuminant'])
 for nm in range(400,701,10): w.writerow([nm]+xyz[nm]+[d65[nm]])
