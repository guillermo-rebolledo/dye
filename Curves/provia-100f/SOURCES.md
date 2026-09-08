# Provia 100F Curve Set

## Measured sources

Fuji Photo Film Co., Ltd., **FUJICHROME PROVIA 100F Professional [RDP III]**,
data sheet AF3-036E:
https://asset.fujifilm.com/master/emea/files/2020-10/2c27854d5609945fbe7e48afc61f815d/films_provia-100f_datasheet_01.pdf

PDF SHA-256: `e28d54e76e8fcdf44c8ffacc930b5b8f2ea54a7cdaeedfcc91790e68eb599de8`.

Unlike the Kodak sheets this project already digitises, Fujifilm draws these
charts as **1-bit raster plates**, not vector paths, so every curve below except
the spectral sensitivities is recovered from ink pixels. The characteristic and
dye-density charts are printed in colour and each arrives as one separation plate
per drawn curve, which is what makes their three curves separable exactly rather
than by inference; the MTF chart is one black plate of one curve, and the
sensitivity chart is the sheet's only vector drawing. Axis calibration comes from
the plate's own frame and grid lines, least-squares fitted after snapping each
detected rule to the nearest printed label, so a grid line the curves or a
caption interrupt is simply absent rather than mis-numbered.

- Page 5, Characteristic Curves: `neutral.red/green/blue.csv`, resampled on a
  uniform 0.05 grid over the drawn span, log H = −3.40…0.80. Coordinates are
  physical log10 lux-seconds and **Fuji FAD-30S Status A** density including
  base density; the spectral model reads them as if they were Status M, which is
  an approximation this Curve Set does not correct for. Density **falls** as
  exposure rises: this is reversal film.
  Where two layers develop neutrally the datasheet draws them on top of one
  another, so green is drawn only down to log H ≈ −1.50 and blue to ≈ −2.15.
  Beyond that each follows the visible curve, with its departure at the junction
  carried to zero over 0.2 log units. That continuation is an **assumption** —
  that a layer not drawn is a layer that coincides with the one covering it —
  not a measurement of an undrawn curve. Each grid sample is the mean of the ink runs within 0.025 log units of it
  rather than one column's own run centre: a printed stroke's edge frays and a
  single centre wanders by a pixel or two, which is well inside the roughly
  0.02-density stroke width but is a corner the Colour Cube would then have to
  follow. Six decimal places preserve extraction reproducibility; they do **not**
  imply six-decimal measurement accuracy.
- Page 5, Spectral Sensitivity Curves: `sensitivity.csv`, 400…700 nm in 10 nm
  increments. This is the one chart the sheet draws as vector paths, sampled at
  101 points per Bezier segment. The chart's log sensitivity is converted to
  linear sensitivity; outside a layer's drawn path the model uses zero, an
  **assumption** rather than a measurement of the unplotted tail. The chart
  describes E-6/CR-56, Status A, 1.0 above D-min.
- Page 5, Spectral Dye Density Curves: `dye-density.csv`. These are the
  **isolated** cyan, magenta and yellow image dyes, which is what Fujifilm
  publishes and Kodak does not — there is no aggregate minimum/midscale neutral
  pair here, and no separation step for the model to perform. The chart is drawn
  peak-normalised, so the extraction reproduces that normalisation exactly; the
  amplitudes the chart omits are solved from this Curve Set's own measured density
  above base at the reference neutral rather than authored.
- Page 5, MTF Curve: `mtf.csv`, sampled on logarithmic frequency and response
  axes and stored as ratios rather than percent. Fujifilm publishes **one**
  curve, not one per layer; the red, green and blue columns therefore carry the
  same values. That is a documented reduction, not a claim of three measurements.
- Page 5, section 16: `rms-granularity.csv`. Diffuse RMS granularity value 8,
  measured through the standard 48 µm aperture at 1.0 above minimum density —
  0.008 density units. Unlike Kodak's Print Grain Index this is the measurement
  the Grain Pass wants, so it is marked measured.
- Page 1: Box Speed 100, daylight. True Speed is equal to Box Speed here; the
  ISO 2240 speed point computed from the digitised curves (the geometric mean of
  the exposures giving D-min + 0.2 and D-min + 2.0) lands at log H = −1.00, which
  is ISO 100 to within the reading, and is what `middleGrayLogExposure` uses.
  Processing tolerance is published as −1/2 to +2 stops, which is the range of
  baked Development Offsets. Stock Balance 5500 K is an artistic daylight
  convention; the sheet specifies a D50 ISO 3664 viewer, not a capture illuminant.
- Pages 2–3: no exposure compensation is required from 1/4000 to 128 seconds, so
  128 s is the measured Reciprocity Failure threshold. At 4 minutes the sheet
  prescribes +1/3 stop and a CC 2.5G filter, and 8 minutes is not recommended.
  The per-channel Schwarzschild exponents are solved from exactly that: the
  aperture correction applies to all three layers and the green filter's 0.025
  density is the extra loss the green layer alone takes, giving p = 0.724 for
  red and blue and 0.633 for green. Marked measured because it is arithmetic on
  the published table rather than a tuned value, but it rests on one data point.

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

These colourimetric tables are not Provia measurements. D65 stands in both for
the manufacturer's unspecified daylight capture spectrum and for the D50 viewer
the sheet actually specifies; because the reversal projection normalises the
Curve Set's own reference neutral to Working Space mid-grey in every channel,
the viewing white cancels and only the dyes' shape survives.

Reproduce the numerical tables with `Scripts/digitize-fujichrome.py`
(PyMuPDF 1.28.2 and NumPy), passing the datasheet, itself again for the dye
plates, the two downloaded CIE files and an output directory. The script pins
the PDF checksum and uses its image plates and vector paths, not a rendered
screenshot or another simulator's profiles. A 0.03 density tolerance covers the
printed stroke width plus interpolation and float16 error.

## Artistic model assumptions

`spectral.json` carries the DIR interaction matrix and the Development Offset
contrast and shadow-loss parameters. Neither is a manufacturer measurement. Only offset 0 has published Characteristic Curves; −0.5, +1 and +2
are tuned predictions inside the sheet's stated processing tolerance and are
never reported as measured step-wedge matches.

The reversal branch views the transparency through the CIE observer and the
viewing illuminant. There is no inversion, no auto-balance beyond the single
reference-neutral normalisation, no shoulder, and no clamp above Working Space
mid-grey: clear film is simply brighter than mid-grey and stays that way until a
file writer clips it. The Stock runs out of density to lose a few stops above the
reference neutral and stops responding there, which is the hard highlight clip
that distinguishes E-6 from C-41 and the near side of its five stops of Latitude. A spectrally flat base at the mean
of the three measured minimum densities stands in for the film support and
residual fog, which is defensible only because reversal film carries no Orange
Mask; it reproduces each measured D-min through any channel and claims nothing
about the base's actual spectrum.

Grain radii, correlation and Density Response, Halation, Bloom, Stock Balance
and the input shaper's use of the ISO 2240 speed point as Working Space mid-grey
are artistic. Metadata Provenance describes each physical field; a measured
source does not make the resulting Colour Cube a measured artifact, and nothing
here constitutes a photographic colour match or independent perceptual validation.

## Reference implementation and licensing

Studied the high-level pipeline and coupler discussion in Andrea Volpato's
[spektrafilm](https://github.com/andreavolpato/spektrafilm) (formerly agx-emulsion),
accessed 2026-09-07. Its repository LICENSE is GPL-3.0; its README separately
identifies CC BY-SA 4.0 profiles and custom LUT terms in SPEKTRAFILM_LICENSE.txt.
No code, profiles, LUTs, digitised curves, or fitted parameters from that project
are incorporated here. This is an independent simplified model using Fujifilm and
CIE source measurements.
