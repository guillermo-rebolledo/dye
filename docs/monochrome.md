# The black & white branch and Contrast Filters

MEM-248 adds the second half of the Film Response Pass. A colour Stock resolves to
a Colour Cube; a black & white Stock resolves to a **Monochrome Collapse** followed
by a **Density Curve**, and **samples no 3D lookup at all**:

```
gray    = sum(max(0, dot(linearRGB, band))) // per-wavelength contributions
density = densityCurve[shaped(gray)]       // per-Stock 1024-entry float16 lookup
```

Tri-X 400, T-Max 100 and Fomapan 100 use this branch, with digitised manufacturer data.

## Nonnegative spectral reconstruction

For colours inside the reconstruction basis, spectral integration reduces exactly
to a three-vector dot product. Outside it, the colour model clamps reconstructed
spectral power at each wavelength. Newly baked B&W Profiles carry
`monochrome.spectralContributions` so they apply the same projection before
collapse, including with Contrast Filters. A dot product alone would integrate
negative spectral power for those colours. Legacy Profiles retain their dot-product
path. Neither path can recover a unique spectrum from RGB.

## The Spectral Weight

`spectralWeight` is what makes two panchromatic Stocks differ. It is **derived by
integrating each Stock's published spectral sensitivity against the CIE colour
matching functions**, never assumed from a luminance weighting — substituting one
would make every B&W Stock in the Catalogue the same Stock with a different
contrast, which is the failure this branch exists to avoid.

The integration reuses `SpectralBasis`, the same colourimetric reconstruction the
colour branch uses: RGB does not determine a spectrum, so the model reconstructs
one from three smooth nonnegative lobes whose 3×3 transform is solved against the
CIE functions. Because that reconstruction is linear in the basis coefficients,

```
gray = ∫ S(λ) · Σ_c coeff_c · basis_c(λ) dλ  =  dot(rgb, rgbToBasisᵀ · raw)
```

collapses to a three-vector only where reconstructed power is nonnegative. New
Profiles retain per-wavelength contributions and clamp before summing, matching
the colour model outside that region too. The reconstructed metamer remains an
approximation.

The Baker derives the weight and writes it into the Profile. Like
`colour.sourceFingerprint` it is **absent from `stock.json`** and rejected if
authored, so a shipped B&W Profile cannot carry a guessed channel mix.

What the two Stocks actually come out as, normalised to sum to one:

| Stock | red | green | blue |
| --- | --- | --- | --- |
| Tri-X 400 | 0.2146 | 0.2399 | 0.5455 |
| T-Max 100 | 0.2106 | 0.2582 | 0.5312 |

Both are blue-led, which is what a panchromatic emulsion under daylight does and
nothing like Rec.2020 luma's 0.678 on green. Tri-X is the bluer of the two and
T-Max the greener, and against a luminance-matched neutral that is worth about
5 % of scan value each way on a blue or a green subject.

**Red-target agreement.** The two stocks separate the test's red subject by less
than one per cent. The tiny direction changes with nonnegative spectral projection
and is not evidence of a meaningful film distinction. Blue and green separate
more strongly; both stocks darken red against the test's luminance-matched neutral.

## Contrast Filters

A Contrast Filter is coloured glass on the lens: a **spectral multiply applied
before the collapse**, and never a tint applied to the developed grey. A red
filter has to darken blue sky, not wash the frame red, and only a model that
reaches the spectrum can express the difference.

The multiply remains inside the spectral integral. Its linear-region summary is:

```
weight_f = rgbToBasisᵀ · ∫ S(λ) · T_f(λ) · basis(λ) dλ
```

The Baker emits one per filter — yellow (Wratten 8), orange (Wratten 15), red
(Wratten 25), green (Wratten 58) and blue (Wratten 47) — and the runtime selects
between their normalized per-wavelength contributions. Legacy Profiles select
the corresponding three-vector.

A filter's weight may carry a small negative component. That is not a defect: it
is the film's response to filtered light resolved back onto the Working Space
primaries, and glass that blocks a primary can push it below zero. Only the
unfiltered collapse is required to be nonnegative.

### Filter factors, and why nothing gets darker

Every weight is stored scaled so the unfiltered one sums to one, which makes each
filter's sum the reciprocal of its **filter factor**. The renderer uses neutral-normalized weights or per-band coefficients, so a Contrast Filter changes tonal separation and leaves exposure
alone — exactly what a photographer does by metering without the glass and opening
up by the published factor. Mid-grey stays at mid-grey through all six settings.
The app's hint names the stops it has already paid.

The factors are also the branch's external check: Kodak publishes a daylight
factor per filter *per film* and the two tables differ. See
[the Contrast Filters' sources](../Curves/contrast-filters/SOURCES.md) for the
derived-against-published table, the 0.7-stop bound, and an honest account of the
remaining source and reconstruction uncertainty.

### Black & white only

A colour Stock has no collapse for glass to act before, so asking for a Contrast
Filter on one is an **error rather than a no-op** — a silently ignored control is
how a look drifts from what the user asked for. A study Profile is black & white
but carries no measured sensitivity, so it has no Contrast Filters and refuses
them the same way. The app offers the picker only where the Profile carries the
weights, and resets the selection when the Stock changes.

## Exposure domain

A measured B&W Curve Set carries `colour.inputShaper`, so the Density Curve is
addressed in physical log10 lux-seconds exactly as a spectral Colour Cube is:

```
gray  = sum(max(0, dot(linearRGB, band)))
logH  = log10(gray / 0.18) + middleGrayLogExposure
coord = clamp((logH - minimumLogExposure) / (maximumLogExposure - minimumLogExposure), 0, 1)
```

The weights sum to one, so a neutral of scene-linear value `v` reaches the curve
at `log10(v/0.18) + middleGray` whichever filter is fitted — which is what makes
the Step Wedge readable in the datasheet's own units and the scan's mid-grey
reference the same point of the curve for every filter.

`colour.cubeOutput` is nil on this branch, because there is no cube whose output
to describe, and the Output Stage is `scan`: the Density Curve returns Density
Space and the runtime inverts and auto-balances it, as it does for the foundation
studies. The foundation study B&W Profiles have no shaper and keep their linear
[0, 1] contract unchanged.

## Validation

`ProfileBaker validate` reports two stages for a measured B&W Stock:

- `measured-density`: a synthetic ramp at every digitised Characteristic Curve
  point and log-space midpoint, rendered through the **public renderer entry
  point** with the scan disabled and compared against the source curve. Worst
  error is 0.0021 for Tri-X and 0.0011 for T-Max against the 0.03 bound. No
  internal Metal pass is a test interface.
- `filter-factor`: derived against published Kodak daylight filter factors, in
  stops, with its own 0.7-stop bound for the reasons the Contrast Filters'
  sources set out.

Both land in the same CSV and SVG report as every other Curve Set, and CI runs
them for every Curve Set on every push.

The shared transmission table now comes from official WRATTEN 2 charts, with
clipped blocking regions recorded as bounds. See the updated filter SOURCES.md and
[accuracy validation](accuracy-validation.md); the 0.7-stop factor gate remains.
