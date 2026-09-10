# Vision3 50D Curve Set

## Measured sources

Eastman Kodak Company, **KODAK VISION3 50D Color Negative Film 5203 / 7203**,
publication H-1-5203t, revised July 2015:
https://www.kodak.com/content/products-brochures/Film/VISION3-50D-Color-Negative-Film-7203-TECHNICAL-DATA.pdf

PDF SHA-256: `adf0dedd974323b4e5d53a54023cd72bc85f447f5f814eb7882774c145d10eeb`.

This sheet is the same publication family and typesetting as
[Vision3 500T's](../vision3-500t/SOURCES.md), so every chart below is drawn as
vector paths and every axis is read from the chart's own drawn plot frame rather
than measured by eye.

- Page 4, Sensitometric Curves: `neutral.red/green/blue.csv`. Coordinates are
  physical log10 lux-seconds and density **including base density**, extracted
  from the drawn Bezier paths using the plot frame's own limits,
  x = −3.03…2.006 and D = 0…3. Both numbers are the chart's printed LOG EXPOSURE
  axis; the chart also carries a secondary "Camera Stops" axis whose −8…+8 span
  implies 0.3148 decades per stop against the 0.30103 a stop actually is, and the
  labelled physical axis is used because it is the one the model needs. Exposure
  5500 K daylight at 1/50 s, Process ECN-2, Status M densitometry.
- Bezier segments are sampled at 101 points each and then resampled on a uniform
  grid of 101 samples spanning the drawn width. Six decimal places preserve
  extraction reproducibility; they do **not** imply six-decimal measurement
  accuracy. Where the drawn stroke's own curvature dips by a thousandth of a
  density in the flat toe, the sample is held to the value before it: a colour
  negative's density only rises with exposure, and a dip a hundredth of the
  stroke's width is not a measurement the Film Response can be a response to.
- Page 4, Spectral Sensitivity Curves: `sensitivity.csv`, sampled at 400…700 nm
  in 10 nm increments. The cyan-, magenta- and yellow-forming layers supply the
  red, green and blue columns. The chart's log sensitivity is converted to linear
  sensitivity. Outside a layer's drawn path, use zero — an **assumption**, not a
  measurement of the unplotted tail. The chart describes 1/10 s effective
  exposure, Status M, 0.2 above D-min. No ultraviolet sensitivity is retained.
- Page 5, Spectral Dye Density Curves: `dye-density.csv`. These are the
  **aggregate** Minimum Density and Midscale Neutral curves, not isolated dye
  spectra. The datasheet does additionally publish peak-normalised cyan, magenta
  and yellow dye curves, which the current negative model does **not** consume:
  its dye separation is artistic Gaussian lobes, exactly as for Portra and 500T.
- Page 3, Modulation-Transfer Function Curves: `mtf.csv`, sampled on logarithmic
  frequency and response axes. Responses are stored as ratios, not percent. R/G/B
  are retained in the CSV; the Profile's single MTF field uses green, a documented
  reduction rather than a claim of three identical MTFs. This chart's frequency
  axis runs to 700 cycles/mm, where 200T's and 500T's run to 600.
- Page 2: Exposure Index 50 in daylight (5500 K), and 12 under 3200 K tungsten
  with a WRATTEN 2 / 80A filter, so Box Speed, True Speed and Stock Balance are
  measured. Page 2 also states no filter or exposure correction is needed for
  exposure times from 1/1000 s to 1 s, which is the Reciprocity Failure
  threshold; the Schwarzschild exponents above one second are an uncalibrated
  assumption and the Profile leaves all three at 1, so the Pass never runs.
- Page 1: an acetate safety base **with rem-jet backing**, which is why this
  Stock's Halation is modelled as suppressed. See below.
- Page 4, Diffuse rms Granularity Curves: **not digitised**. Reading the
  nomograph requires combining two curves through a right-hand sigma-D scale.
  `rms-granularity.csv` records an artistic 0.006 density-unit assumption and the
  Profile marks it artistic.

`observer.csv` is byte-identical to the Portra 400 and Vision3 500T Curve Sets'
file: the official CIE 1931 2° colour matching functions and standard illuminant
D65, sampled without interpolation at 10 nm, from
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

Reproduce the numerical tables with `Scripts/digitize-vision3.py vision3-50d`
(PyMuPDF 1.28.2), passing the downloaded datasheet, the two CIE files and an
output directory. The script pins the PDF checksum and uses its vector paths, not
a rendered screenshot or another simulator's profiles.

## Artistic model assumptions

- `format: 135`. Kodak 5203 is a 35 mm **motion picture** stock whose camera
  aperture is narrower than the 36 mm 135 still frame. The app renders still
  photographs, so this Profile adopts the 135 Frame Width and every Film-Plane
  Micron radius converts through 36 mm. Provenance marks `format` artistic. A
  motion-picture format with its own Frame Width would be the honest fix, and it
  would be the same fix for all four Vision3 Stocks.
- `colour.inputShaper` spans −3.08…2.056 log10 lux-seconds so the digitised
  curves sit inside it, with reference gray at −0.54. That reference is Portra's
  −1.44 moved by the ratio of the two box speeds, log10(400/50); it is a choice,
  not a Kodak aim density, and it is marked artistic. It is the same rule the
  other three Vision3 Curve Sets use, which is what makes the four comparable.
- `spectral.json` is byte-identical to Vision3 500T's: the DIR interaction
  matrix, dye lobe centres and widths, scan gamma and the Development Offset
  contrast/shadow-loss parameters are the Portra model's, reused unchanged. No
  separate tuning was done for this Stock. Only offset 0 has published
  Characteristic Curves; the −1/+1/+2 variants are tuned predictions and are
  never reported as measured.
- Halation is artistic. `strength` 0.008 and radii 180/80/40 µm are the values
  Vision3 500T carries, and they are deliberately identical across all four ECN-2
  Stocks: what suppresses halation here is the rem-jet backing Kodak states on
  page 1, which every Vision3 stock has and no still colour negative does.
  Nobody publishes a number for it. Portra 400's 0.03 and 220/90/45 µm are the
  still-negative comparison, and Cinestill 800T's 0.55 is what the same emulsion
  does once the rem-jet is washed off.
- Grain, Bloom, the scanner and Reciprocity Failure above one second are
  artistic. `grainRadiusMicrons` 1.0 is the finest in the Catalogue, which is the
  ordering the four Vision3 speeds imply and not a measurement.
- The RA-4 paper this Stock's Print Output Stage prints onto is
  [its own Curve Set](../ra4-paper/SOURCES.md); what is artistic about the
  enlarger is recorded there.

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
