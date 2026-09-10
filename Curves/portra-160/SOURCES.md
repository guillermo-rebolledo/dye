# Portra 160 Curve Set

## Measured sources

Kodak Alaris, **KODAK PROFESSIONAL PORTRA 160 Film**, publication E-4051,
revised February 2016:
https://imaging.kodakalaris.com/sites/prod/files/files/products/e4051_Portra_160.pdf

PDF SHA-256: `a635048fc5e578747868684ff5a98fa2a6582a5d4542dd4ba2e132bc06d951c0`.

The digitiser calibrates every chart from its own drawn plot box and then checks
that box against the chart's printed tick labels, refusing to write anything if
a label sits more than 2.5 points from the axis it names. Channel assignment is
read off the chart too, from the vertical order of its B/G/R labels and the
horizontal position of its layer names, rather than from PDF drawing order. Both
checks are in `Scripts/digitize-portra-160.py`; neither was done by eye.

- Page 4, Characteristic Curves: `neutral.red/green/blue.csv`. Coordinates are
  physical log10 lux-seconds and **Status M** density, including base density.
  Chart limits x = −4…1, D = 0…4. The drawn curves span approximately −3.03…0.95.
  Do not silently shift these into the foundation studies' normalized exposure
  convention. Unlike Portra 400's, these curves are drawn as Bezier paths rather
  than polylines, so there are no vertices to extract; they are sampled on a
  uniform 0.02 log-exposure grid, a **reduction** rather than a measurement of
  200 independent points. Bezier sampling leaves dips of a few times 1e-5 density
  along the curves, and the blue toe dips about 0.002 density just above its
  start. Both are one to two orders below the printed 0.02-density stroke width.
  The digitiser takes the running maximum so the result is monotone, as the Baker
  requires, and aborts if that correction ever approaches the stroke width.
- Page 4, Spectral-Sensitivity Curves: `sensitivity.csv`. Cubic Bezier paths
  sampled at 101 points per segment, linearly interpolated at 400…700 nm in
  10 nm increments. Chart limits 250…750 nm and log sensitivity 3…−1; note that
  this differs from Portra 400's 4…0 range, which is why the digitiser reads the
  range from the chart rather than assuming the family shares one. Converted to
  linear sensitivity. Outside a layer's drawn path, use zero (an **assumption**,
  not a measurement of the unplotted tail). The chart describes daylight,
  1/50 s, Status M, 0.2 above D-min. The recovered peaks fall at 630, 550 and
  470 nm for the cyan-, magenta- and yellow-forming layers, which is the
  independent physical check that the layers were not transposed.
- Page 4, Spectral-Dye-Density Curves: `dye-density.csv`. Same vector sampling,
  chart limits 400…700 nm, D = 0…2.5. These are **aggregate** minimum and midscale
  neutral densities, not isolated cyan/magenta/yellow dye spectra. Isolated dye
  separation is artistic.
- Page 4, Modulation Transfer Function: `mtf.csv`. Vector paths sampled on
  logarithmic frequency and response axes, chart limits 1…600 cycles/mm and
  200…1 percent. Responses stored as ratios, not percent. The drawn curves stop
  at approximately 80 cycles/mm, so the grid stops at 70 rather than extrapolate;
  Portra 400's runs to 80 and the two grids are therefore not identical. R/G/B
  are retained in the CSV; the Profile's single MTF field uses green, a
  documented reduction rather than a claim of three identical MTFs. Green exceeds
  blue at high frequency here, where on Portra 400 blue is highest.
- Page 3, Print Grain Index: `print-grain-index.csv`, the 135-format table
  (28, 50, 79 at 4.4×, 8.8× and 17.8×), against Portra 400's 37, 59 and 89.
  **Kodak explicitly says PGI replaces RMS granularity and cannot be compared
  to it.** No RMS measurement is published in this edition. `rms-granularity.csv`
  therefore records an artistic 0.006 density-unit assumption, chosen below
  Portra 400's 0.008 because the PGI table is lower, not because 0.006 was
  measured. The Profile marks it artistic.
- Page 4, the Characteristic Curves' own annotation: Log H Ref −1.051, which is
  `colour.inputShaper.middleGrayLogExposure`. Portra 400's is −1.44.
- Page 1: Box Speed 160 and available formats. True Speed is assumed equal to
  Box Speed. Stock Balance 5500 K is an artistic daylight convention.
- Page 2: no filter correction or exposure compensation from 1/10,000 second to
  1 second; the threshold is measured, but the longer-exposure Schwarzschild
  exponent is an uncalibrated assumption.

`observer.csv`: official CIE 1931 2° colour matching functions and standard
illuminant D65, sampled without interpolation at 10 nm:
https://files.cie.co.at/CIE_xyz_1931_2deg.csv and
https://files.cie.co.at/CIE_std_illum_D65.csv.
Attribution: International Commission on Illumination (CIE), Vienna, 2019,
“Colour-matching functions of CIE 1931 standard colorimetric observer”,
DOI [10.25039/CIE.DS.xvudnb9b](https://doi.org/10.25039/CIE.DS.xvudnb9b), and
“CIE standard illuminant D65”, DOI
[10.25039/CIE.DS.hjfjmt59](https://doi.org/10.25039/CIE.DS.hjfjmt59).
Both source datasets and the resampled/combined `observer.csv` are licensed
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
Changes: retain 400…700 nm at 10 nm intervals and combine into one table.
Source SHA-256 checksums are respectively
`fa663e3535a7e0763a745993a1f0a192eb0275ac46ad2d1befd7626841e713c1` and
`e76f210bffff3d552ef7113025da5f325d5dfec200dd4b878b1a2f3a507032cb`.
The file is byte-identical to Portra 400's for that reason.

These colourimetric tables are not Portra 160 measurements. The D65 reference is
an artistic surrogate for the manufacturer's unspecified daylight spectrum.

Reproduce the numerical tables with `Scripts/digitize-portra-160.py`
(PyMuPDF 1.28.2), passing the three downloaded files and an output directory.
The script pins the PDF checksum and uses its vector paths, not a rendered
screenshot or another simulator's profiles. Six decimal places preserve
extraction reproducibility; they do **not** imply six-decimal measurement
accuracy. The 0.03 density tolerance carried over from Portra 400 covers the
printed curve's roughly 0.02-density stroke width plus interpolation and float16
error. CI must meet this bound; colour accuracy is a separate question.

## Artistic model assumptions

`spectral.json` contains the DIR interaction matrix (density-dependent inhibition
in log exposure), broad dye lobe centres/widths, scan gamma, and Development
Offset contrast/shadow-loss parameters. They are not manufacturer measurements.
The couplers are lighter than Portra 400's because Portra 160 is the family's
lowest-contrast, least saturated member; that is a tuned judgement about the look
described in the datasheet's prose, not a measurement of inhibition.
The −1/+1/+2 variants modify curve shape about the published log H reference
−1.051, preserving its exposure rather than multiplying scene brightness.
Only offset 0 has published Characteristic Curves; the other variants are tuned
predictions and are never reported as measured step-wedge matches.

RMS, Grain radii/correlation/density response, Halation, True Speed, Reciprocity
Failure above one second, and the scanner are artistic. Grain radius and Halation
strength are set below Portra 400's on the datasheet's claim of finer grain; the
numbers themselves are invented. Metadata Provenance describes each physical
field, with additional spectral source/model markers; a measured source does not
make the resulting Colour Cube a measured artifact.

## Reference implementation and licensing

As for Portra 400: Andrea Volpato's
[spektrafilm](https://github.com/andreavolpato/spektrafilm) was studied for its
high-level pipeline and coupler discussion only. No code, profiles, LUTs,
digitised curves, or fitted parameters from that project are incorporated here.
This is an independent simplified model using Kodak and CIE source measurements.
It does not claim numerical parity with spektrafilm or its ports, or independent
perceptual validation of Portra 160 colour.

## Rights

Attribution: Kodak Alaris, for the published datasheets and technical publications cited
above. This repository contains **independent numerical readings and an extraction
script**, not the source PDFs and not reproduced chart artwork. Extracting numerical
facts from a published chart is a different act from reproducing the chart, and this
project keeps to the former.

**No open-content licence is claimed for Kodak Alaris's material.** Nothing in `Curves/`
ships inside the application; only the baked
`Sources/FilmEngine/Catalogue/*.filmprofile` files do. Dye is not affiliated with,
endorsed by, or sponsored by Kodak Alaris. See the repository's `NOTICE.md`.

CIE data in this directory is separately licensed CC BY-SA 4.0; see `NOTICE.md`.
