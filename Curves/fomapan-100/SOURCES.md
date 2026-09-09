# Fomapan 100 Classic Curve Set

**This Profile is an Approximation.** Its spectral sensitivity carries a scale the
datasheet does not print, and the app labels the Stock accordingly. Everything on
this page distinguishes what Foma published from what was assumed here.

## Measured sources

FOMA BOHEMIA, **FOMAPAN 100 Classic**, black-and-white negative film datasheet:
https://www.foma.cz/en/fomapan-100

PDF SHA-256: `44d0913f0413d89d61c004ae926d73a51fcb94d32b5892b8de03d19827cc8d5f`.

Foma draws its charts as filled outlines rather than stroked centrelines, so the
vector paths give the two edges of a curve and never the curve itself. The charts
are rendered at 600 dpi and traced from ink instead, the way the Fujichrome and
Vision3 250D raster plates are. At that resolution the 0.5 pt stroke is four pixels
wide, so this is a change of representation rather than of source. Grid rules
locate both axes and the tracer refuses a chart whose rule count has changed.

- Page 1, Characteristic curves: `density.csv`. Foma prints three curves, for 5, 7
  and 11 minutes in Microphen. **The 7-minute curve is taken** — the middle of the
  three and inside the sheet's own recommended 5–7 minutes — and the other two are
  discarded. They are the Stock's own push and pull, which the monochrome branch
  does not model, so this Curve Set has one Density Curve and no variants.
- The same chart's horizontal axis is **relative** log exposure: Foma publishes no
  reference point of any kind, unlike Kodak's Log H Ref. The curve is anchored to
  physical log10 lux-seconds through the **ISO speed point**, which ISO 6 places at
  0.1 above base density at H = 0.8 / S lux-seconds. Box speed ISO 100 puts that at
  −2.097. The anchoring uses only the published speed and the standard's own
  definition, but it is an **assumption**, not a measurement, and `colour.inputShaper`
  is marked artistic. `middleGrayLogExposure` sits 1.116 log units above the speed
  point, the mean of the two offsets Kodak publishes outright for Tri-X 400 and
  T-Max 100, which are the only two Stocks in the Catalogue that state both numbers.
- Page 1, Granularity: `rms-granularity.csv`. **RMS = 13.5**, Microphen at 20 °C
  developed to gamma 0.6, measured at D = 1.0, which is 0.0135 in density units.
  This is a real published RMS figure, unlike Kodak's Print Grain Index, and the
  Profile marks `grain.rmsGranularity` measured. The grain radius beside it is not.
- Page 1, Schwarzschild effect: the sheet's lengthening table (1× to 1/2 second,
  then 2× at 1 s, 8× at 10 s, 16× at 100 s) is fitted by least squares in log-log
  to the engine's own gain, `(t / T)^(p − 1)` with T = 1/2 second, giving p = 0.43.
  Both `reciprocity` fields are marked measured: the threshold is stated outright
  and the exponent is a two-parameter fit to four published points, not a guess.
- Page 1, Speed: ISO 100/21°. True Speed is taken as Box Speed, which Foma's own
  text supports for this Stock.
- Page 1, Resolving power: 110 lines per mm. `mtf.csv` is **not a published MTF**
  and Foma prints none. It is a Gaussian whose response falls to a tenth at the
  published resolving power, which is the conventional reading of that figure. Both
  MTF fields are marked artistic.

## The spectral sensitivity, and why it is an Approximation

Page 1, Relative spectral sensitivity (wedge spectrogram at 2850 K):
`sensitivity.csv`. The horizontal axis is a 50 nm ladder whose first rule is the
frame's own left edge at 400 nm, labelled every second rule. **The vertical axis
carries no scale at all** — no ticks, no numbers, only the symbol Sλ. A wedge
spectrogram's vertical axis is log sensitivity by convention, so the shape is
recoverable and the units are not.

The trace reads the box as one decade of log sensitivity. That span is an
assumption and it is the reason the Profile is an Approximation. The recovered
shape is right in the way that can be checked — a smooth rise from 400 nm to a peak
at 640 nm and a sharp cutoff by 670 nm, which is what a panchromatic emulsion does
— and the scale is not checkable from this sheet.

There is no `filter-factors.csv`. Foma publishes no daylight filter factors, and
Kodak's table is Kodak's: comparing weights derived from Foma's curve against
Tri-X's published factors would test Tri-X. The validator now runs its
`filter-factor` stage only for a Stock whose manufacturer publishes one, so this
Curve Set's report has a `measured-density` stage and nothing else. That is an
honest absence rather than a passing check, and `spectral.contrastFilters` and
`spectral.sensitivity` are both marked `approximation`. The Contrast Filter picker
still works; what is missing is independent evidence that it is right for this film.

For the record, the derived factors sit about 0.9 stops from the generic Wratten
values in blue and about 1.0 stop in red, in the direction Foma's own spectrogram
implies: more red sensitivity and less blue than a Kodak panchromatic. Choosing the
decade span to close that gap was tried and rejected — it fits the film's spectral
shape away to satisfy numbers that are not its own.

`observer.csv`: official CIE 1931 2° colour matching functions and standard
illuminant D65, sampled without interpolation at 10 nm, identical to the other
measured Curve Sets' copy. Attribution: International Commission on Illumination
(CIE), Vienna, 2019, DOI [10.25039/CIE.DS.xvudnb9b](https://doi.org/10.25039/CIE.DS.xvudnb9b)
and DOI [10.25039/CIE.DS.hjfjmt59](https://doi.org/10.25039/CIE.DS.hjfjmt59), both
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). D65 is an artistic
surrogate; the spectrogram itself is at 2850 K, which the model does not reproduce.

Reproduce the tables with `Scripts/digitize-foma.py`, passing the stock name, the
downloaded datasheet, the two CIE files and an output directory. The script pins
the PDF checksum.

## Artistic model assumptions

Grain radius, the Density Response, Halation, Bloom, Stock Balance and the MTF are
artistic. Halation strength is zero, as for the other silver Stocks. The measured
density gate holds to 0.0016 density against the digitised curve, well inside the
0.03 bound; that measures the bake and the render, not Foma's colour.
