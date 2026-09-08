# T-Max 100 Curve Set

## Measured sources

Kodak Alaris, **KODAK PROFESSIONAL T-MAX 100 Film**, publication F-4016,
revised February 2016:
https://imaging.kodakalaris.com/sites/default/files/files/resources/f4016_TMax_100.pdf

PDF SHA-256: `a9899179ed86d4419bbb996ab2cbbece338c602975e16961cba5dd69ee96d3fe`.

- Page 8, Characteristic Curves, KODAK PROFESSIONAL T-MAX Developer, small tank,
  20 °C, **7 minutes**: `density.csv`. The datasheet's small-tank table (page 3)
  recommends 7½ minutes in T-MAX (1:4) at 20 °C; 7 minutes is the nearest
  **plotted** time, and the substitution is a documented approximation rather
  than a match. The same developer and tank as Tri-X 400's curve, so the two
  Stocks' contrast is compared like for like. Coordinates are physical log10
  lux-seconds and diffuse visual density including base+fog; chart limits
  x = −4…1, D = 0…3. The drawn curve spans approximately −3.15…0.65.
- Page 8, Spectral Sensitivity Curves: `sensitivity.csv`. Cubic Bézier paths
  sampled at 101 points per segment and linearly interpolated at 400…700 nm in
  10 nm increments, converting the chart's log sensitivity to linear
  sensitivity. Chart limits 250…750 nm, log sensitivity −2…2. The chart
  describes a **tungsten** effective exposure of 1.4 seconds read by diffuse
  visual densitometry, where F-4017's Tri-X chart names no illuminant; the two
  curves are therefore not measured under identical conditions, which is a real
  limitation on comparing them and is not corrected for here.

  The curve used is the one labelled **0.3 greater than D-min**, the upper of
  the two plotted criteria. F-4016 labels its two curves in place rather than in
  a legend, which is what settles the equivalent ambiguity in F-4017; see
  [Tri-X's sources](../tri-x-400/SOURCES.md).

  Outside the drawn path the model holds the first plotted value below the
  curve's start at 400.4 nm and uses zero above its end at 701 nm. Both are
  **assumptions**, not measurements of the unplotted tails.
- Page 8, Modulation Transfer Curves: `mtf.csv`. Vector paths sampled on
  logarithmic frequency and response axes, both calibrated by least squares over
  the chart's own printed tick labels (worst residual 0.8 pt, about 1.2 % of
  response). Responses stored as ratios, not percent. The chart runs far enough
  to record 0.78 at 80 cycles/mm where Tri-X is at 0.25 at 70, which is the
  sharpness difference between the two Stocks and not an artefact of sampling.
- Page 8, Image Structure: `rms-granularity.csv`. Diffuse rms granularity **8**,
  read at a net diffuse density of 1.00 through a 48 µm aperture at 12×. Stored
  in density units as 0.008. Kodak measures it in D-76 rather than the T-MAX
  Developer the Characteristic Curve is plotted in. Resolving power is also
  published (63 lines/mm at TOC 1.6:1, 200 lines/mm at 1000:1); the Profile has
  no field for it and the MTF carries the same information continuously.
- Page 1: Box Speed 100 and the 135 format. Page 2, Filter Corrections,
  **daylight** column: `filter-factors.csv`. Wratten No. 8 = 1.5, No. 15 = 2,
  No. 25 = 8, No. 58 = 6, No. 47 = 8. Kodak's own note that "filter factors for
  other Kodak black-and-white films are different" is the published statement
  that these two Stocks do not see colour alike.
- Page 2: no exposure compensation from 1/1000 through 1/10 second; the
  reciprocity threshold of one second is measured. The datasheet does publish a
  long-exposure compensation table, but the Profile's three Schwarzschild
  exponents stay at 1 and are marked artistic: a single exponent of 0.849 does
  reproduce both of Kodak's published points exactly, so this is a modelling
  opportunity left open rather than a fit that failed. A monochrome Stock has one
  emulsion, so its three exponents would in any case be equal and carry none of
  the colour shift the per-layer model exists for.

`observer.csv`: official CIE 1931 2° colour matching functions and standard
illuminant D65, sampled without interpolation at 10 nm, byte-identical to
[Portra's](../portra-400/SOURCES.md) and carrying the same attribution, licence
and checksums. It is not a T-Max measurement.

Reproduce the numerical tables with `Scripts/digitize-t-max-100.py` (PyMuPDF
1.28.2), passing the three downloaded files and an output directory. The script
pins the PDF checksum and uses its vector paths.

## What the digitisation is checked against

- **ISO speed.** The digitised curve reaches 0.10 above base at log H = −2.257,
  which by ISO 6's `S = 0.8 / H_m` is **ISO 145** against a Box Speed of 100.
  Unlike Tri-X's ISO 415, this is not a confirmation: ISO 6 defines the speed in
  a specified developer and this chart is plotted in T-MAX Developer, which is
  speed-enhancing, so half a stop over box speed is expected rather than
  alarming. It is recorded because it is what the digitisation actually says.
  The Profile records True Speed as Box Speed and marks it artistic.
- **Filter factors.** See [the Contrast Filters](../contrast-filters/SOURCES.md).
  Derived against published, in stops: yellow +0.63, orange +0.45, red +0.04,
  green +0.02, blue −0.17. Yellow and orange are the worst residuals in the
  repository and are discussed there.

## Artistic model assumptions

As for [Tri-X](../tri-x-400/SOURCES.md): Stock Balance, zero Halation, the
modelled lens's Bloom, the Density Response curve, channel correlation, True
Speed and the Schwarzschild exponent. Grain radius is 0.8 µm against Tri-X's
1.6 µm, an artistic reading of a tabular-grain emulsion against a cubic one;
the measured granularity difference (0.008 against 0.017) is what actually
carries the Grain Pass.

`colour.inputShaper` places mid-grey at log H = −1.053, the digitised speed point
plus the four stops between Zone I and Zone V.

## Reference implementation and licensing

No code, profiles, LUTs, digitised curves or fitted parameters from any other
film-simulation project are incorporated here.
