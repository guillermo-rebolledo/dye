# Tri-X 400 Curve Set

## Measured sources

Kodak Alaris, **KODAK PROFESSIONAL TRI-X 320 and 400 Films**, publication F-4017,
revised February 2016:
https://imaging.kodakalaris.com/sites/default/files/files/resources/f4017_TriX.pdf

PDF SHA-256: `51d738f4f996c98716d153bab75e41d0359637a18ea49f9be52062652b0b27d2`.

- Page 7, Characteristic Curves, **TRI-X 400 Film / 400TX, 35 mm**: `density.csv`.
  KODAK PROFESSIONAL T-MAX Developer, small tank, 30-second agitation, 20 °C,
  **6 minutes** — the solid curve, and the time the datasheet's own small-tank
  table recommends for this film, developer and temperature (page 3). Coordinates
  are physical log10 lux-seconds and diffuse visual density including base+fog;
  chart limits x = −4…1, D = 0…4. Extracted all vector polyline vertices. The
  drawn curve spans approximately −3.45…0.35.
  The other three plotted times (7, 9, 11 minutes) are not baked: the black &
  white branch has no Development Offset variants, so a Profile carries the one
  normally developed curve.
- Page 7, Spectral Sensitivity Curves: `sensitivity.csv`. Cubic Bézier paths
  sampled at 101 points per segment and linearly interpolated at 400…700 nm in
  10 nm increments, converting the chart's log sensitivity to linear sensitivity.
  Chart limits 250…750 nm, log sensitivity 0…4. The chart describes an effective
  exposure of 0.5 second read by diffuse visual densitometry.

  **Which of the two plotted criteria this is.** The chart plots sensitivity at
  D = 0.3 and at D = 1.0 above gross fog, and this Curve Set uses the **upper,
  more sensitive** curve, which is the D = 0.3 criterion: Kodak's own footnote
  defines sensitivity as the reciprocal of the exposure required to reach a
  density, so the lower criterion must sit higher on the chart. The F-4017
  legend's dash patterns pair the *solid* sample line with the D = 1.0 label,
  which contradicts that; the equivalent chart in F-4016 labels its curves in
  place and puts 0.3 above 1.0, and the filter-factor validation below agrees
  with the upper curve to 0.19 stops and with the lower one only to 0.40. The
  discrepancy is in the published legend, and the choice is recorded here rather
  than hidden.

  Outside the drawn path the model holds the first plotted value below 400 nm —
  the chart truncates the curve at its plotting limit rather than the film
  ending there — and uses zero above the last drawn wavelength, 669 nm, where
  the curve leaves through the bottom of the chart at roughly 0.2 % of peak.
  Both are **assumptions**, not measurements of the unplotted tails. No
  ultraviolet or infrared sensitivity is retained by the visible model.
- Page 7, Modulation Transfer Function: `mtf.csv`. Vector paths sampled on
  logarithmic frequency and response axes, both calibrated by least squares over
  the chart's own printed tick labels (worst residual 0.8 pt, about 1.2 % of
  response). Responses stored as ratios, not percent. The chart is not labelled
  for one of the two films the datasheet covers; it is read here as Tri-X 400,
  a documented reduction rather than a claim.
- Page 6, Image Structure: `rms-granularity.csv`. Diffuse rms granularity **17**,
  read at a net diffuse density of 1.0 through a 48 µm aperture at 12× — the
  measurement the Grain Pass's Selwyn scaling is defined against, so unlike
  Portra this Stock's granularity is `measured` rather than assumed. Stored in
  density units as 0.017. Kodak measures it in HC-110 (B) rather than the T-MAX
  Developer the Characteristic Curve is plotted in.
- Page 1: Box Speed 400 and the 135 format. Filter Corrections table, **daylight**
  column, for TRI-X 400 Film / 400TX: `filter-factors.csv`. Wratten No. 8 = 2,
  No. 15 = 2.5, No. 25 = 8, No. 58 = 6, No. 47 = 6.
- Page 2: no exposure compensation from 1/1000 through 1/10 second; the
  reciprocity threshold of one second is measured. The datasheet does publish a
  long-exposure compensation table, but the Profile's three Schwarzschild
  exponents stay at 1 and are marked artistic: no single exponent fits Kodak's
  exposure column (0.40 fitted at 10 s against 0.55 at 100 s), and the table
  couples every exposure increase to a development change the model has no term
  for. A monochrome Stock has one
  emulsion, so its three exponents would in any case be equal and carry none of
  the colour shift the per-layer model exists for.

`observer.csv`: official CIE 1931 2° colour matching functions and standard
illuminant D65, sampled without interpolation at 10 nm, byte-identical to
[Portra's](../portra-400/SOURCES.md) and carrying the same attribution, licence
and checksums. It is not a Tri-X measurement, and D65 is an artistic surrogate
for the manufacturer's unspecified daylight.

Reproduce the numerical tables with `Scripts/digitize-tri-x-400.py` (PyMuPDF
1.28.2), passing the three downloaded files and an output directory. The script
pins the PDF checksum and uses its vector paths, not a rendered screenshot or
another simulator's profiles. Six decimal places preserve extraction
reproducibility; they do **not** imply six-decimal measurement accuracy.

## What the digitisation is checked against

The Curve Set is not self-certifying, so two numbers nobody in this repository
chose are recovered from it:

- **ISO speed.** The digitised curve reaches 0.10 above base at log H = −2.715,
  which by ISO 6's `S = 0.8 / H_m` is **ISO 415** against a Box Speed of 400.
  That the exposure axis lands within 4 % of the printed speed is the evidence
  that the chart calibration is right and the axis really is absolute
  lux-seconds. The Profile still records True Speed as Box Speed and marks it
  artistic; 415 is a check, not a rating.
- **Filter factors.** See [the Contrast Filters](../contrast-filters/SOURCES.md).
  Derived against published, in stops: yellow +0.26, orange +0.15, red +0.01,
  green +0.09, blue +0.19.

## Artistic model assumptions

Stock Balance 5500 K is a daylight convention and means little for a Stock with
no colour to balance; it still decides what the White Balance Pass adapts
toward, which for a black & white Stock changes the light the Monochrome Collapse
sees and therefore genuinely matters.

Halation strength is zero: Tri-X carries an effective anti-halation backing and
neither datasheet publishes a scattering figure, so the Pass is off rather than
guessed. Bloom is the same modelled taking lens every Profile carries. Grain
radius 1.6 µm, the Density Response curve, channel correlation and the input
shaper's placement of mid-grey are artistic; the Spectral Weight, the Contrast
Filter weights, the MTF, the granularity and the Characteristic Curve are not.

`colour.inputShaper` places mid-grey at log H = −1.511, which is the digitised
speed point plus 1.204 — the four stops between Zone I and Zone V. That is a
metering convention rather than a Kodak measurement, and it is what makes 0.18
scene-linear light land where a correctly exposed mid-tone lands on the film.

## Reference implementation and licensing

No code, profiles, LUTs, digitised curves or fitted parameters from any other
film-simulation project are incorporated here. This is an independent model
built from Kodak and CIE source measurements, and it does not claim perceptual
validation against a real Tri-X negative.
