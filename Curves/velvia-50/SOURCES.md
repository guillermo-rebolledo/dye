# Velvia 50 Curve Set

## Measured sources

Fujifilm, **FUJICHROME Velvia 50 Professional [RVP 50]**, product information
bulletin AF3-0221E2:
https://asset.fujifilm.com/master/emea/files/2020-10/a71dda63e2662f012b3b74110794918a/films_velvia-50_datasheet_01.pdf

PDF SHA-256: `668844e4cf81d5d234645c90d0b3217ed81c3be925a063b4752f7a71c3954d4c`.

Fujifilm draws these charts as **1-bit raster plates**, not vector paths, so
every curve below is recovered from ink pixels. Unlike Provia's, Velvia's four
charts are printed in one colour each, so curves are told apart by line style or
by their own extent rather than by separation plate — see the limitations below.
Axis calibration comes from each plate's own frame and grid lines, least-squares
fitted after snapping each detected rule to the nearest printed label.

- Page 8, Characteristic Curves: `neutral.red/green/blue.csv`, resampled on a
  uniform 0.05 grid over the drawn span, log H = −2.85…1.10. Coordinates are
  physical log10 lux-seconds and **Status A** density including base density;
  the spectral model reads them as if they were Status M, which is an
  approximation this Curve Set does not correct for. Density **falls** as
  exposure rises: this is reversal film.
  Red is drawn solid, green dash-dot and blue dashed, and the three separate
  only above D ≈ 3.0, where they stay in that order. The three are tracked as
  branches of the plate's ink runs and interpolated across the dashes' gaps;
  below the separation all three land on the single drawn line, which is what
  the chart is asserting. Each grid sample is the mean of the ink runs within 0.025 log units of it
  rather than one column's own run centre: a printed stroke's edge frays and a
  single centre wanders by a pixel or two, which is well inside the roughly
  0.02-density stroke width but is a corner the Colour Cube would then have to
  follow. Six decimal places preserve extraction reproducibility; they do **not**
  imply six-decimal measurement accuracy.
- Page 8, Spectral Sensitivity Curves: `sensitivity.csv`, 400…700 nm in 10 nm
  increments. The three layers occupy nearly disjoint bands, so they are
  recovered as the plate's three longest ink chains and assigned blue, green and
  red by wavelength; the printed layer labels fall out as chains too short to be
  curves. The chart's log sensitivity is converted to linear sensitivity;
  outside a layer's drawn path the model uses zero, an **assumption** rather
  than a measurement of the unplotted tail. E-6/CR-56, Status A, 1.0 above D-min.
- Page 8, MTF Curve: `mtf.csv`, sampled on logarithmic frequency and response
  axes and stored as ratios rather than percent. Fujifilm publishes **one**
  curve, not one per layer; the red, green and blue columns therefore carry the
  same values. That is a documented reduction, not a claim of three measurements.
- Page 7, section 17: `rms-granularity.csv`. Diffuse RMS granularity value 9,
  measured through the standard 48 µm aperture at 1.0 above minimum density —
  0.009 density units, and a real measurement rather than Kodak's Print Grain Index.
- Page 1: Box Speed 50, daylight, and a published processing tolerance of −1/2
  to +1 stop, which is the range of baked Development Offsets. The ISO 2240
  speed point computed from the digitised curves (the geometric mean of the
  exposures giving D-min + 0.2 and D-min + 2.0) lands at log H = −0.685, which is
  ISO 48 — the box speed to within the reading — and is what
  `middleGrayLogExposure` uses. **True Speed is 40, not 50**: metering Velvia at
  its box speed is widely held to underexpose it, and the sheet publishes nothing
  either way, so `trueISO` is artistic. Stock Balance 5500 K is an artistic
  daylight convention; the sheet specifies a D50 ISO 3664 viewer.
- Page 2: no compensation from 1/4000 to 1 second, so 1 s is the measured
  Reciprocity Failure threshold, and the sheet then tabulates 4 s (+1/3 stop,
  CC 5M), 8 s (+1/2, 7.5M), 16 s (+2/3, 10M) and 32 s (+1 stop, 12.5M), with
  64 s not recommended. The per-channel Schwarzschild exponents are a
  least-squares fit through the origin to exactly that table: the aperture
  correction is the loss the red and blue layers take, and the magenta filter's
  density is the loss the green layer does *not* take, giving p = 0.818 for red
  and blue and 0.901 for green. Marked measured because it is arithmetic on the
  published table; the fit treats CC-M as green-only, which it approximately is.

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

These colourimetric tables are not Velvia measurements. D65 stands in both for
the manufacturer's unspecified daylight capture spectrum and for the D50 viewer
the sheet specifies; because the reversal projection normalises the Curve Set's
own reference neutral to Working Space mid-grey in every channel, the viewing
white cancels and only the dyes' shape survives.

## The dye set is Provia's, and is not a Velvia measurement

`dye-density.csv` is digitised from **Provia 100F's** Spectral Dye Density
Curves, not Velvia's, and `spectral.dyeDensity` is marked artistic here for that
reason. Velvia's own chart (page 8) publishes the same isolated cyan, magenta
and yellow dyes, but prints all three in one colour, and they cross one another
twice. Where two curves cross, their ink merges into a single run for a few
columns and the two branches step apart on either side by more than the local
slope predicts, so neither position tracking nor slope continuation resolves
which branch is which — and a wrong assignment is not a small error, it is two
dyes swapped over half the spectrum. Rather than ship a separation that cannot
be defended, the Curve Set borrows the Fujichrome E-6 dye set that *can* be
separated exactly, from its colour-plate sibling.

This is an approximation. The two stocks share a process and a manufacturer, and
Velvia's published dye curves resemble Provia's, but they are not the same dyes,
and this substitution is a plausible reason for Velvia's rendered hues to be
wrong in a way the step wedge cannot detect. Replacing it needs either a
colour-plate edition of the Velvia sheet or a separation method with better
evidence than tracking — not a tolerance change.

## Artistic model assumptions

`spectral.json` carries the DIR interaction matrix and the Development Offset
contrast and shadow-loss parameters. Velvia's much stronger DIR matrix is what
the model expresses its saturation with, alongside its own steep curve; it is
tuned, not measured, and the datasheet publishes no inter-image data at all.
Only offset 0 has published Characteristic Curves; −0.5 and +1 are tuned
predictions inside the sheet's stated processing tolerance and are never
reported as measured step-wedge matches.

The reversal branch views the transparency through the CIE observer and the
viewing illuminant. There is no inversion, no auto-balance beyond the single
reference-neutral normalisation, no shoulder, and no clamp above Working Space
mid-grey: clear film is simply brighter than mid-grey and stays that way until a
file writer clips it. The Stock runs out of density to lose a few stops above the
reference neutral and stops responding there, which is the hard highlight clip
that distinguishes E-6 from C-41 and the near side of its five stops of Latitude. A spectrally flat base at the mean
of the three measured minimum densities stands in for the film support and
residual fog, defensible only because reversal film carries no Orange Mask.

Grain radii, correlation and Density Response, Halation, Bloom, True Speed,
Stock Balance and the input shaper's use of the ISO 2240 speed point as Working
Space mid-grey are artistic. Metadata Provenance describes each physical field;
a measured source does not make the resulting Colour Cube a measured artifact,
and nothing here constitutes a photographic colour match.

## Reference implementation and licensing

Studied the high-level pipeline and coupler discussion in Andrea Volpato's
[spektrafilm](https://github.com/andreavolpato/spektrafilm) (formerly agx-emulsion),
accessed 2026-09-07. Its repository LICENSE is GPL-3.0; its README separately
identifies CC BY-SA 4.0 profiles and custom LUT terms in SPEKTRAFILM_LICENSE.txt.
No code, profiles, LUTs, digitised curves, or fitted parameters from that project
are incorporated here. This is an independent simplified model using Fujifilm and
CIE source measurements.
