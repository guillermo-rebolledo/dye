# Vision3 250D Curve Set

## Measured sources

Eastman Kodak Company, **KODAK VISION3 250D Color Negative Film 5207 / 7207**,
publication H-1-5207, March 2022:
https://www.kodak.com/content/products-brochures/Film/VISION3-250D-Technical-Data-EN.pdf

PDF SHA-256: `69094a9cecdfe2fae752a96c1f471bddf1cb514c83513757b6587a3de6432799`.

**This sheet is a later and differently typeset edition than the other three
Vision3 stocks'**, which are the July 2015 `H-1-…t` family. It draws its charts
as **antialiased raster plates** rather than as vector paths, so its curves are
recovered from ink pixels the way the Fujichrome plates are — see
[Velvia 50's sources](../velvia-50/SOURCES.md) for the same technique. That has
two consequences this Curve Set records honestly, one about method and one about
what could be read at all.

Axis calibration comes from each plate's own frame and grid lines, least-squares
fitted after snapping each detected rule to the nearest printed label. Before any
curve is read, the plate is reduced to the ink connected to its own frame: every
curve either runs to the frame or crosses a rule that meets it, and every caption
and layer label printed inside the plot area is a component of its own, so this
drops the printing without naming a rectangle for each piece of it.

- Page 3, Sensitometric Curves: `neutral.red/green/blue.csv`. Coordinates are
  physical log10 lux-seconds and density **including base density**, over the
  plate's own limits x = −3.7…1.1 and D = 0…3, resampled to 101 uniform samples.
  Exposure 5500 K daylight at 1/50 s, Process ECN-2, Status M densitometry. The
  three layers never change places, so they are tracked as three branches of the
  plate's ink runs from the first column that separates all three. Each grid
  sample is the mean of the tracked points within half a step of it rather than
  one column's own run centre: a printed stroke's edge frays and a single centre
  wanders by a pixel or two, which is well inside the stroke width but is a corner
  the Colour Cube would then have to follow. Where the result still dips, it is
  held to the value before it, because a colour negative's density only rises.
  Six decimal places preserve extraction reproducibility; they do **not** imply
  six-decimal measurement accuracy. The chart's LOG EXPOSURE and "Camera Stops"
  axes agree at 0.30103 decades per stop, as 200T's do and 50D's and 500T's
  do not.
- Page 3, Modulation-Transfer Function Curves: `mtf.csv`, on logarithmic
  frequency and response axes, stored as ratios rather than percent. The three
  curves coincide below about 20 cycles/mm and again above about 60, where the
  chart draws one line and all three tracks land on it — which is what the chart
  is asserting, not a failure to separate them. R/G/B are retained in the CSV;
  the Profile's single MTF field uses green, a documented reduction.
- Page 1: an acetate safety base **with rem-jet backing**.
- Page 2: Exposure Index 250 in daylight (5500 K), and 64 under 3200 K tungsten
  with a WRATTEN 2 / 80A filter, so Box Speed, True Speed and Stock Balance are
  measured. Page 2 also states no filter or exposure correction is needed for
  exposure times from 1/1000 s to 1 s, which is the Reciprocity Failure
  threshold; the Schwarzschild exponents above one second are an uncalibrated
  assumption and the Profile leaves all three at 1.
- Page 2, Diffuse rms Granularity Curves: **not digitised**, as for the other
  three. `rms-granularity.csv` records an artistic 0.009 density-unit assumption.

### What this sheet could not supply

`sensitivity.csv` and `dye-density.csv` are **taken from the Vision3 50D Curve
Set**, and both are marked **approximation** in this Profile's Provenance because they
are not this Stock's own measurements.

The plates are there — page 3 publishes both charts — but neither separates. The
Spectral Sensitivity plate draws three layers in one colour that cross twice, at
about 505 nm and about 600 nm, where each is steep in the opposite direction; the
Spectral Dye Density plate draws five curves in one colour, of which the
Midscale Neutral is not the topmost across the whole band (the peak-normalised
cyan dye rises above it beyond about 660 nm) and the Minimum Density is a dashed
curve that passes under two others. No separation of either is reliable enough to
call a measurement, and a reading that is wrong in a way nobody can see is worse
than a borrowing that is written down.

50D is the other daylight-balanced VISION3 negative and shares this Stock's dye
chemistry and sensitiser family, which is what makes the borrowing defensible
rather than arbitrary — the same argument, and the same disclosure, that lets
Velvia 50 borrow Provia 100F's dye set. What it costs is real: 250D and 50D see
colour identically in this Catalogue. What still distinguishes 250D is its own
Characteristic Curves, its own MTF, its own speed and its own grain, which is
what the two Stocks actually differ by most.

Kodak no longer publishes a vector edition of this sheet. If one becomes
available, replacing these two files with 250D's own measurements is a data
change rather than a model change.

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

Reproduce the numerical tables with
`Scripts/digitize-vision3.py vision3-250d` (PyMuPDF 1.28.2 and NumPy), passing
**both** this datasheet and 50D's, then the two CIE files and an output
directory. The script pins both PDFs' checksums.

## Artistic model assumptions

- `format: 135`, for the reason 50D's Curve Set records: 5207 is a motion picture
  stock and the app renders still photographs.
- `colour.inputShaper` spans −3.75…1.15 log10 lux-seconds so the digitised curves
  sit inside it, with reference gray at −1.24 — Portra's −1.44 moved by
  log10(400/250). A choice, not a Kodak aim density, and marked artistic.
- `spectral.json` is byte-identical to Vision3 500T's, which is Portra's model
  reused unchanged. Only offset 0 has published Characteristic Curves; the
  −1/+1/+2 variants are tuned predictions and never reported as measured.
- Halation is artistic, and identical to the other three Vision3 Stocks':
  `strength` 0.008 and radii 180/80/40 µm, suppressed by the rem-jet backing.
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
