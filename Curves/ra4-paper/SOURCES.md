# RA-4 paper

This directory holds no `stock.json` and is **not a Stock**. It is the colour
paper the Print Output Stage enlarges a negative onto, and a paper belongs to the
darkroom rather than to any one film, so every Curve Set that prints reads one
copy of it from here — exactly as every monochrome Curve Set reads one copy of
[the Contrast Filters' transmittance table](../contrast-filters/SOURCES.md). The
bake and validate loops skip directories without a `stock.json` for that reason.

## Measured sources

Eastman Kodak Company, **KODAK PROFESSIONAL ENDURA Premier Paper**, publication
E-4070, March 2013:
https://business.kodakmoments.com/sites/default/files/files/resources/paper-endura-techpub-e4070.pdf

PDF SHA-256: `6f632cc5943a4adb8da487b86470ddf51c436a52f313241691b5b8b2bab1718f`.

Kodak draws every chart in this publication as vector paths, so each curve is
read from its own Bezier segments and each axis from the chart's drawn plot
frame, as the Vision3 sheets are.

- Page 4, Characteristic Curves: `density.csv`, headed
  `logExposure,red,green,blue` because the paper's three layers are measured
  together where a Stock's are one file each. Coordinates are physical log10
  lux-seconds at the paper and Status A **reflection** density including the
  paper's D-min, over the plot frame's own limits x = −3.0…0.0 and D = 0…3,
  resampled to 101 uniform samples. Exposure 0.5 s, Process RA-4 at 95 °F
  (35 °C) for 45 s. The measured D-min is 0.105/0.106/0.080 and the measured
  D-max 2.757/2.525/2.443. Where the drawn stroke's own curvature dips by a
  thousandth of a density the sample is held to the value before it: paper
  density only rises with exposure.
- Page 4, Spectral-Sensitivity Curves: `sensitivity.csv`, sampled at 400…700 nm
  in 10 nm increments. The cyan-, magenta- and yellow-forming layers supply the
  red, green and blue columns; log sensitivity is converted to linear
  sensitivity. Outside a layer's drawn path the model uses zero, an
  **assumption** rather than a measurement of the unplotted tail.
- Page 5, Spectral-Dye-Density Curves: `dye-density.csv`, the **isolated** cyan,
  magenta and yellow image dyes as Kodak draws them, peak-normalised to 1.0 —
  the same shape of table a reversal Stock supplies, and for the same reason: the
  chart gives the dyes' shapes and not their amplitudes.

Six decimal places preserve extraction reproducibility; they do **not** imply
six-decimal measurement accuracy.

Reproduce the tables with `Scripts/digitize-ra4-paper.py` (PyMuPDF 1.28.2),
passing the downloaded datasheet and an output directory. The script pins the PDF
checksum.

## What is measured and what is not

The paper is measured. The **darkroom around it is not**, and every part of that
is marked `spectral.enlarger` artistic in each printing Profile:

- **The enlarger lamp** is modelled as a 3200 K Planckian radiator — a
  tungsten-halogen head, which is the light this paper's own sensitometry is
  exposed under. Only its shape matters; the exposure solve absorbs any scale.
- **The dichroic filter pack** is modelled as three subtractive filters whose
  transmittance shapes are the paper's *own* peak-normalised dyes: a yellow
  filter holds back the blue-sensitive layer the way the yellow dye absorbs blue.
  Real dichroics are sharper than dye absorptions. The pack's three densities
  sum to zero, because a pack's common part is neutral density, which is an
  exposure time rather than a colour, and lives in the exposure instead.
- **The aim** is Kodak's Laboratory Aim Density for a reflection print, a neutral
  at 1.0 density. What is *solved* rather than authored is which three dye
  amounts reach that density **neutrally**: the three dyes are not a visual
  neutral in equal Status A amounts, and a print whose mid-scale was Status A
  neutral would carry that difference all the way to its paper white, where there
  is no dye left to hide it.
- **A layer's Status A density is read as its dye's amount**, on the
  peak-normalised curve. That is exact only to the extent that Status A measures
  one dye at its own peak, which is what Status A is for and not quite what it
  achieves.
- **The Viewing Light** is the same D65 and CIE 1931 2° observer the Transparency
  is read by, from each Stock's own `observer.csv`. A print viewed under a
  tungsten room light is a different picture, and this model does not offer one.

## Limitations

- The paper's cyan-forming layer peaks at about 695 nm, at the very edge of the
  400…700 nm band every table in this project shares. Its peak is inside the
  band, but its long tail is not, so the red layer's integral is short of the
  light a real print's red layer receives. What that costs is absorbed by the
  filter pack, which is solved against the same truncated integral.
- The paper's D-min is modelled as spectrally flat at the mean of its three
  measured minimum densities, as a Transparency's base is. A real paper white
  carries an optical brightener and is not flat.
- One paper. Kodak alone published dozens, and a printer's choice of paper is as
  much of the look as the negative is. If the Catalogue ever wants a second, this
  directory is where it goes, and the Profile schema would have to say which one
  each print cube was baked against rather than assuming this one.
