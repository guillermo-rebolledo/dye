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
  densitometry **ECN-2**, not Status M; ECN-2 names the process, not a separate standard density status. Kodak process
  control uses Status M, but this caption alone does not resolve the measurement
  conditions. No invented conversion is applied.
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
  spectra. `isolated-dye-density.csv` separately records the published
  peak-normalised cyan, magenta and yellow curves on the same 400–700 nm grid.
  The small **signed** lobes are retained: the chart is a D-min-subtracted
  dye/mask density difference, not three independently nonnegative absorbers.
  No clipping or second peak normalization is applied during digitisation.
- Page 3, Modulation-Transfer Function Curves: `mtf.csv`, sampled on logarithmic
  frequency and response axes. Responses are stored as ratios, not percent. R/G/B
  are retained in the CSV; the baked Profile retains all three channel responses. The legacy shared MTF
  field remains green for compatibility.
- Page 2: Exposure Index 500 under tungsten (3200 K), and no filter or exposure
  correction for exposure times from 1/1000 s to 1 s. Box Speed, True Speed,
  Stock Balance and the Reciprocity Failure threshold are therefore measured; the
  Schwarzschild exponent above one second is an uncalibrated assumption.
- Page 4, Diffuse rms Granularity Curves: `granularity.csv`, measured sigma-D
  against **absolute channel density** (including base), at the published
  48 µm microdensitometer aperture. This is distinct from the legacy
  `rms-granularity.csv` artistic 0.014 scalar, which remains unchanged by the
  extraction. The new table is restricted to the common measured density range
  0.95–2.00, at 0.01 intervals; no extrapolation is present in the source table.
  Its `red`, `green`, `blue` values are sigma in density units, not the customary
  displayed RMS number multiplied by 1000, and not display-RGB noise amplitudes.

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

Reproduce the numerical tables with `Scripts/digitize-vision3.py vision3-500t` (PyMuPDF
1.28.2), passing the downloaded datasheet, the two CIE files and an output
directory. The script pins the PDF checksum and uses its vector paths, not a
rendered screenshot or another simulator's profiles.

### Additional extraction checks (2026-09-10)

The pinned PDF above was downloaded, its SHA-256 verified, and pages 4 and 5
visually inspected against their vector drawings. All seven previously emitted
CSVs (`neutral.*`, sensitivity, aggregate dye density, MTF and observer)
reproduce **byte-for-byte** with the extended script.

On page 5, drawing indices 30/29/28 identify cyan/magenta/yellow, confirmed by
their labelled peaks at approximately 685/539/446 nm. Axis calibration is the
same as the existing aggregate extraction. The full drawn paths peak at
1.0030/1.0009/1.0044 rather than precisely 1.0; these small printed/extraction
deviations are preserved. Magenta reaches approximately −0.0397 in its short
wavelength lobe; this is visible in the chart and is not floating-point noise.
Unweighted least-squares fitting of the 31 sampled CMY curves to the existing
`midscale − minimum` spectrum gives amplitudes 0.741316/0.699259/0.773772,
RMS residual 0.004531 density and maximum residual 0.010774 density. Those are
**internal fit diagnostics**, not independent photographic validation or exact
isolated dye concentrations. The sampled basis has condition number about 1.42.

For granularity, page 4 solid drawings 47/46/45 are red/green/blue density.
Dashed blue is drawing 48; drawing 49 contains two continuous subpaths,
items 0–115 green and 116–231 red. Treating drawing 49 as one sorted curve
would mix different channel measurements. The digitizer checks these subpaths'
continuity. The left axis spans density 0–3; the right sigma-D axis is fitted in
log10 space to all 15 tick marks from 0.001 to 0.1. Maximum tick-fit residual is
0.000500 log10 sigma (about 0.12%).

Each sample follows Kodak's instructions: start at a channel density, find the
solid curve's horizontal coordinate, then read the same channel's dashed curve
and convert its height through the right axis. The intermediate horizontal axis
is **relative exposure**. It is never relabelled as physical log exposure or
aligned by eye with the separate characteristic chart. The three density curves
span approximately 0.210–2.008 red, 0.596–2.717 green and 0.893–2.970 blue, so
the common grid 0.95–2.00 needs no endpoint holding. The lower bound also
avoids a small nonmonotonic blue toe at density 0.899–0.902, where the inverse
nomograph would be ambiguous. At density 1.0 the table
gives sigma-D 0.006045/0.010608/0.030697; these represent **different exposures**
for the three channels. A consumer must look up each channel's own developed
density, not use one common RGB luminance as all three measurement coordinates.

The approximately one-point curve stroke represents about 0.016 density on the
left nomograph axis and 4% sigma on its logarithmic right axis (full stroke
widths, not confidence intervals). The half-stroke positional uncertainty is
about ±0.008 density or ±2% sigma before combining interpolation, density-to-
exposure mapping and specimen/instrument variability. Near a flat solid curve,
horizontal-coordinate uncertainty can be much larger. Kodak also warns that
the granularity and sensitometric curves use different equipment. Six decimal
places in these CSVs preserve reproducibility and do not imply measurement
precision. Spatial grain size, channel covariance, other apertures, and values
outside the extracted density interval remain unmeasured by these tables.

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
- Halation, grain radii/correlation, the scanner and Reciprocity Failure above one second are
  artistic. Halation `strength` 0.008 reflects that this Stock has a Remjet
  anti-halation backing, which Kodak states on page 1; the number itself is
  published by nobody. It is the value Cinestill 800T departs from.

## Reference implementation and licensing

This Curve Set reuses the model built for Portra 400, whose
[SOURCES.md](../portra-400/SOURCES.md) records the same statement: the high-level
pipeline and coupler discussion in Andrea Volpato's
[spektrafilm](https://github.com/andreavolpato/spektrafilm) were studied, and no
code, profiles, LUTs, digitised curves or fitted parameters from that project are
incorporated. This is an independent simplified model over Kodak and CIE source
measurements. It does not claim numerical parity with any other implementation, or
independent perceptual validation of Vision3 colour.

## Rights

Attribution: Eastman Kodak Company, for the published datasheets and technical publications cited
above. This repository contains **independent numerical readings and an extraction
script**, not the source PDFs and not reproduced chart artwork. Extracting numerical
facts from a published chart is a different act from reproducing the chart, and this
project keeps to the former.

**No open-content licence is claimed for Eastman Kodak Company's material.** Nothing in `Curves/`
ships inside the application; only the baked
`Sources/FilmEngine/Catalogue/*.filmprofile` files do. Dye is not affiliated with,
endorsed by, or sponsored by Eastman Kodak Company. See the repository's `NOTICE.md`.

CIE data in this directory is separately licensed CC BY-SA 4.0; see `NOTICE.md`.
