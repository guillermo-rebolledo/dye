# Vision3 200T Curve Set

## Measured sources

Eastman Kodak Company, **KODAK VISION3 200T Color Negative Film 5213 / 7213**,
publication H-1-5213t, revised July 2015:
https://www.kodak.com/content/products-brochures/Film/VISION3-200T-Color-Negative-Film-7213-TECHNICAL-DATA.pdf

PDF SHA-256: `c2a88cb5de19c40e991f7522f9c7a43ea4c59357ccdca6957a4f5e31f2abd411`.

This sheet is the same publication family and typesetting as
[Vision3 500T's](../vision3-500t/SOURCES.md) and
[50D's](../vision3-50d/SOURCES.md), so every chart below is drawn as vector paths
and every axis is read from the chart's own drawn plot frame.

- Page 4, Sensitometric Curves: `neutral.red/green/blue.csv`. Coordinates are
  physical log10 lux-seconds and density **including base density**, extracted
  from the drawn Bezier paths using the plot frame's own limits,
  x = −3.684…1.116 and D = 0…3, resampled to 101 uniform samples across that
  width. Exposure 3200 K at 1/50 s, Process ECN-2, Status M densitometry. This
  chart's LOG EXPOSURE and "Camera Stops" axes agree: its 4.8-decade span over
  sixteen stops is 0.30103 decades per stop exactly, unlike 50D's and 500T's.
  Six decimal places preserve extraction reproducibility; they do **not** imply
  six-decimal measurement accuracy.
- Page 4, Spectral Sensitivity Curves: `sensitivity.csv`, sampled at 400…700 nm
  in 10 nm increments. The cyan-, magenta- and yellow-forming layers supply the
  red, green and blue columns; log sensitivity is converted to linear
  sensitivity. Outside a layer's drawn path, use zero — an **assumption**, not a
  measurement of the unplotted tail. The chart describes 1/25 s effective
  exposure, Status M, 0.2 above D-min. No ultraviolet sensitivity is retained.
- Page 5, Spectral Dye Density Curves: `dye-density.csv`. These are the
  **aggregate** Minimum Density and Midscale Neutral curves, not isolated dye
  spectra; the peak-normalised cyan, magenta and yellow curves the sheet also
  publishes are not consumed, because the negative model's dye separation is
  artistic Gaussian lobes.
- Page 3, Modulation-Transfer Function Curves: `mtf.csv`, sampled on logarithmic
  frequency and response axes. Responses are ratios, not percent. R/G/B are
  retained in the CSV; the Profile's single MTF field uses green, a documented
  reduction rather than a claim of three identical MTFs.
- Page 2: Exposure Index 200 under 3200 K tungsten, and 125 in daylight with a
  WRATTEN 2 / 85 filter, so Box Speed, True Speed and Stock Balance are measured.
  **Feeding a 5500 K scene through this Stock produces a heavy blue cast, and
  that is correct**: the film is manufactured for 3200 K light and the renderer
  does not correct it away. The White Balance control is what corrects it, if the
  photographer wants it corrected.
- Page 2 also states no filter or exposure correction is needed for exposure
  times from 1/1000 s to 1 s, which is the Reciprocity Failure threshold; the
  Schwarzschild exponents above one second are an uncalibrated assumption and the
  Profile leaves all three at 1, so the Pass never runs.
- Page 1: an acetate safety base **with rem-jet backing**, which is why this
  Stock's Halation is modelled as suppressed. See below.
- Page 4, Diffuse rms Granularity Curves: **not digitised**, for the same reason
  as the other three. `rms-granularity.csv` records an artistic 0.011
  density-unit assumption and the Profile marks it artistic.

`observer.csv` is byte-identical to the other Kodak Curve Sets' file: the
official CIE 1931 2° colour matching functions and standard illuminant D65,
sampled without interpolation at 10 nm, from
https://files.cie.co.at/CIE_xyz_1931_2deg.csv and
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

These colourimetric tables are not Vision3 measurements. As for 500T, the D65
reference is an artistic surrogate: this is a tungsten Stock, and the model's
internal neutral reference is unchanged from the daylight case. The renderer's
White Balance Pass, not this table, is what makes a daylight scene record blue.

Reproduce the numerical tables with `Scripts/digitize-vision3.py vision3-200t`
(PyMuPDF 1.28.2), passing the downloaded datasheet, the two CIE files and an
output directory. The script pins the PDF checksum and uses its vector paths.

## Artistic model assumptions

- `format: 135`, for the reason 50D's Curve Set records: 5213 is a motion picture
  stock and the app renders still photographs.
- `colour.inputShaper` spans −3.734…1.166 log10 lux-seconds so the digitised
  curves sit inside it, with reference gray at −1.14 — Portra's −1.44 moved by
  log10(400/200). A choice, not a Kodak aim density, and marked artistic.
- `spectral.json` is byte-identical to Vision3 500T's, which is Portra's model
  reused unchanged. Only offset 0 has published Characteristic Curves; the
  −1/+1/+2 variants are tuned predictions and never reported as measured.
- Halation is artistic, and identical to the other three Vision3 Stocks':
  `strength` 0.008 and radii 180/80/40 µm. What suppresses it is the rem-jet
  backing Kodak states on page 1. Nobody publishes a number for it.
- Grain, Bloom, the scanner and Reciprocity Failure above one second are
  artistic. `grainRadiusMicrons` 1.3 is the ordering the four Vision3 speeds
  imply and not a measurement.
- The RA-4 paper this Stock's Print Output Stage prints onto is
  [its own Curve Set](../ra4-paper/SOURCES.md).

## Reference implementation and licensing

This Curve Set reuses the model built for Portra 400, whose
[SOURCES.md](../portra-400/SOURCES.md) records the same statement: the high-level
pipeline and coupler discussion in Andrea Volpato's
[spektrafilm](https://github.com/andreavolpato/spektrafilm) were studied, and no
code, profiles, LUTs, digitised curves or fitted parameters from that project are
incorporated. This is an independent simplified model over Kodak and CIE source
measurements. It does not claim numerical parity with any other implementation, or
independent perceptual validation of Vision3 colour.
