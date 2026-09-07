# Portra 400 Curve Set

## Measured sources

Kodak Alaris, **KODAK PROFESSIONAL PORTRA 400 Film**, publication E-4050,
revised February 2016:
https://imaging.kodakalaris.com/sites/default/files/files/resources/e4050_portra_400.pdf

PDF SHA-256: `e83ac6775d37832a4cb466892a3e1cf4c88917a6ee93384e59d6924b1cd97e3a`.

- Page 4, Characteristic Curves: `neutral.red/green/blue.csv`. Coordinates are
  physical log10 lux-seconds and **Status M** density, including base density.
  Extracted all vector polyline vertices, using chart limits x = −4…1, D = 0…4.
  The actual drawn curves span approximately −3.44…0.56. Do not silently shift
  these into the foundation studies' normalized exposure convention.
- Page 4, Spectral-Sensitivity Curves: `sensitivity.csv`. Cubic Bezier paths
  sampled at 101 points per segment, linearly interpolated at 400…700 nm in
  10 nm increments. Convert the chart's log sensitivity to linear sensitivity.
  Outside a layer's drawn path, use zero (an **assumption**, not a measurement
  of the unplotted tail). The chart describes daylight, 1/50 s, Status M,
  0.2 above D-min. No ultraviolet sensitivity is retained by the visible model.
- Page 4, Spectral-Dye-Density Curves: `dye-density.csv`. Same vector sampling,
  chart limits 400…700 nm, D = 0…2.5. These are **aggregate** minimum and midscale
  neutral densities, not isolated cyan/magenta/yellow dye spectra. Roundoff at
  the PDF chart edges is endpoint-clamped. Isolated dye separation is artistic.
- Page 4, Modulation Transfer Function: `mtf.csv`. Vector paths sampled on
  logarithmic frequency and response axes. Responses stored as ratios, not
  percent. R/G/B retained in CSV; the existing Profile's single MTF field uses
  green, a documented reduction rather than a claim of three identical MTFs.
- Page 3, Print Grain Index: `print-grain-index.csv`, the 135-format table.
  **Kodak explicitly says PGI replaces RMS granularity and cannot be compared
  to it.** No RMS measurement is published in this edition. `rms-granularity.csv`
  therefore records an artistic 0.008 density-unit assumption. It is not
  digitised Kodak RMS, and the Profile marks it artistic. The literal ticket
  request for measured RMS cannot be satisfied from this datasheet.
- Page 1: Box Speed 400 and available formats. True Speed is assumed equal to
  Box Speed. Stock Balance 5500 K is an artistic daylight convention.
- Page 2: no exposure compensation through 1 second; the threshold is measured,
  but the longer-exposure Schwarzschild exponent is an uncalibrated assumption.

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

These colourimetric tables are not Portra measurements. The D65 reference is an
artistic surrogate for the manufacturer's unspecified daylight spectrum.

Reproduce the numerical tables with `Scripts/digitize-portra.py` (PyMuPDF 1.28.2),
passing the three downloaded files and an output directory. The script pins the
PDF checksum and uses its vector paths, not a rendered screenshot or another
simulator's profiles. Six decimal places preserve extraction reproducibility;
they do **not** imply six-decimal measurement accuracy. A 0.03 density tolerance
covers the printed curve's roughly 0.02-density stroke width plus interpolation
and float16 error. CI must meet this bound; colour accuracy is a separate question.

## Artistic model assumptions

`spectral.json` contains the DIR interaction matrix (density-dependent inhibition
in log exposure), broad dye lobe centres/widths, scan gamma, and Development
Offset contrast/shadow-loss parameters. They are not manufacturer measurements.
The −1/+1/+2 variants modify curve shape about the published log H reference
−1.44, preserving its exposure rather than multiplying scene brightness.
Only offset 0 has published Characteristic Curves; the other variants are tuned
predictions and are never reported as measured step-wedge matches.

RMS, Grain radii/correlation/density response, Halation, True Speed, Reciprocity
Failure above one second, and the scanner are artistic. No spatial effects are
applied by this ticket. Metadata Provenance describes each physical field, with
additional spectral source/model markers; a measured source does not make the
resulting Colour Cube a measured artifact.

## Reference implementation and licensing

Studied the high-level pipeline and coupler discussion in Andrea Volpato's
[spektrafilm](https://github.com/andreavolpato/spektrafilm) (formerly agx-emulsion),
accessed 2026-09-07. Its repository LICENSE is GPL-3.0; its README separately
identifies CC BY-SA 4.0 profiles and custom LUT terms in SPEKTRAFILM_LICENSE.txt.
No code, profiles, LUTs, digitised curves, or fitted parameters from that project
are incorporated here. This is an independent simplified model using Kodak and
CIE source measurements. It does not claim numerical parity with spektrafilm or
its ports, or independent perceptual validation of Portra colour.
