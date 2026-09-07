# Vision3 500T Curve Set

## Measured sources

Eastman Kodak Company, **KODAK VISION3 500T Color Negative Film 5219 / 7219 /
SO-219**, publication H-1-5219t, revised July 2015:
https://www.kodak.com/content/products-brochures/Film/VISION3-500T-Color-Negative-Film-7219-TECHNICAL-DATA.pdf

PDF SHA-256: `06eca2287fbaf57a1aeacbb8151bbd48e23aefb30af2114b412e9c1c63f4d1db`.

- Page 4, Characteristic Curves: `neutral.red/green/blue.csv`. Coordinates are
  physical log10 lux-seconds and density **including base density**, extracted
  from the drawn Bezier paths using the chart limits x = −4…1, D = 0…3. The
  curves are drawn across the full plotted width. Kodak labels this chart's
  densitometry **ECN-2**, not Status M; the spectral model reads it as if it were
  Status M, which is an approximation this Curve Set does not correct for.
  The chart carries a secondary "Camera Stops" axis whose −8…+8 span disagrees
  with the labelled −4…1 log-exposure span by about 4%. The labelled physical
  axis is used, because it is the one the model needs.
- Bezier segments are sampled at 101 points each and then resampled on a uniform
  0.05 log-exposure grid, 101 samples per curve. Against the densely sampled
  path this loses at most 0.0008 density, far under the roughly 0.02-density
  stroke width. Six decimal places preserve extraction reproducibility; they do
  **not** imply six-decimal measurement accuracy.
- Page 4, Spectral Sensitivity Curves: `sensitivity.csv`, sampled at 400…700 nm
  in 10 nm increments. The cyan-, magenta- and yellow-forming layers supply the
  red, green and blue columns. The chart's log sensitivity is converted to linear
  sensitivity. Outside a layer's drawn path, use zero — an **assumption**, not a
  measurement of the unplotted tail. The chart describes 1/25 s effective
  exposure, Status M, 0.2 above D-min. No ultraviolet sensitivity is retained.
- Page 5, Spectral Dye Density Curves: `dye-density.csv`. These are the
  **aggregate** Minimum Density and Midscale Neutral curves, not isolated dye
  spectra. This datasheet does additionally publish peak-normalised cyan, magenta
  and yellow dye curves, which the current model does **not** consume: its dye
  separation is artistic Gaussian lobes, exactly as for Portra. Using the
  published isolated curves would be a model change, not a data change.
- Page 3, Modulation-Transfer Function Curves: `mtf.csv`, sampled on logarithmic
  frequency and response axes. Responses are stored as ratios, not percent. R/G/B
  are retained in the CSV; the Profile's single MTF field uses green, a documented
  reduction rather than a claim of three identical MTFs.
- Page 2: Exposure Index 500 under tungsten (3200 K), and no filter or exposure
  correction for exposure times from 1/1000 s to 1 s. Box Speed, True Speed,
  Stock Balance and the Reciprocity Failure threshold are therefore measured; the
  Schwarzschild exponent above one second is an uncalibrated assumption.
- Page 4, Diffuse rms Granularity Curves: **not digitised**. The datasheet does
  publish a granularity nomograph for this Stock, but reading it requires
  combining two curves through a right-hand sigma-D scale, and no Grain Pass
  consumes the result yet. `rms-granularity.csv` records an artistic 0.014
  density-unit assumption and the Profile marks it artistic.

`observer.csv` is byte-identical to the Portra 400 Curve Set's file: the official
CIE 1931 2° colour matching functions and standard illuminant D65, sampled without
interpolation at 10 nm, from https://files.cie.co.at/CIE_xyz_1931_2deg.csv and
https://files.cie.co.at/CIE_std_illum_D65.csv. Attribution: International
Commission on Illumination (CIE), Vienna, 2019, “Colour-matching functions of CIE
1931 standard colorimetric observer”, DOI
[10.25039/CIE.DS.xvudnb9b](https://doi.org/10.25039/CIE.DS.xvudnb9b), and “CIE
standard illuminant D65”, DOI
[10.25039/CIE.DS.hjfjmt59](https://doi.org/10.25039/CIE.DS.hjfjmt59). Both source
datasets and the resampled/combined `observer.csv` are licensed
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Changes: retain
400…700 nm at 10 nm intervals and combine into one table. Source SHA-256 checksums
are respectively `fa663e3535a7e0763a745993a1f0a192eb0275ac46ad2d1befd7626841e713c1`
and `e76f210bffff3d552ef7113025da5f325d5dfec200dd4b878b1a2f3a507032cb`.

These colourimetric tables are not Vision3 measurements. The D65 reference is an
artistic surrogate: this is a tungsten Stock, and the model's internal neutral
reference is unchanged from the daylight case. The renderer's White Balance Pass,
not this table, is what makes a daylight scene record blue on this Stock.

Reproduce the numerical tables with `Scripts/digitize-vision3-500t.py` (PyMuPDF
1.28.2), passing the downloaded datasheet, the two CIE files and an output
directory. The script pins the PDF checksum and uses its vector paths, not a
rendered screenshot or another simulator's profiles.

## Artistic model assumptions

- `format: 135`. Kodak 5219 is a 35 mm **motion picture** stock whose camera
  aperture is narrower than the 36 mm 135 still frame. The app renders still
  photographs, so this Profile adopts the 135 Frame Width and every Film-Plane
  Micron radius converts through 36 mm. Provenance marks `format` artistic. A
  motion-picture format with its own Frame Width would be the honest fix.
- `colour.inputShaper` spans −4.05…1.05 log10 lux-seconds so the digitised curves
  sit inside it, with reference gray at −1.54. That reference is Portra's −1.44
  scaled by the speed ratio log10(500/400); it is a choice, not a Kodak aim
  density, and it is marked artistic. At −1.54 the layers sit 0.69/0.81/0.78
  density above base, comparable to Portra at its own reference.
- `spectral.json` carries the DIR interaction matrix, dye lobe centres and widths,
  scan gamma and the Development Offset contrast/shadow-loss parameters. The DIR
  matrix is the Portra model's matrix reused unchanged: no separate tuning was
  done for this Stock. Only offset 0 has published Characteristic Curves; the
  −1/+1/+2 variants are tuned predictions and are never reported as measured.
- Halation, Grain, the scanner and Reciprocity Failure above one second are
  artistic. Halation `strength` 0.008 reflects that this Stock has a rem-jet
  anti-halation backing, which Kodak states on page 1; the number itself is
  published by nobody. It is the value CineStill 800T departs from.

## Reference implementation and licensing

This Curve Set reuses the model built for Portra 400, whose
[SOURCES.md](../portra-400/SOURCES.md) records the same statement: the high-level
pipeline and coupler discussion in Andrea Volpato's
[spektrafilm](https://github.com/andreavolpato/spektrafilm) were studied, and no
code, profiles, LUTs, digitised curves or fitted parameters from that project are
incorporated. This is an independent simplified model over Kodak and CIE source
measurements. It does not claim numerical parity with any other implementation, or
independent perceptual validation of Vision3 colour.
