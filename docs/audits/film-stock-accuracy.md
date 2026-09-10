# Film stock accuracy audit

Date: 2026-09-10. Code inspected: `98ba1ec`. Scope: the shipped film engine,
Curve Sets, profile baking, image intake, and validation. This is a source and
data audit, not an on-device visual review. The companion
[primary-source research](film-stock-accuracy-research.md) supplies external evidence.

## Assessment

The engine has a useful measured foundation, but photographic accuracy is not yet
established. Digitized characteristic curves, spectral sensitivities, reproducible
bakes and regression tests constrain parts of the pipeline. The scanner, dye
separation, interlayer interactions, development variants and several spatial
parameters still contain assumptions that can dominate the final appearance.

The most immediate finding is a **grain calibration defect affecting all nine
shipped measured/derived colour profiles**: the renderer samples middle gray at
the wrong cube coordinate. A CPU probe of the committed profiles finds a zero
grain envelope at actual middle gray in every one. Fixing that has a clearer
justification than further artistic tuning.

For the next calibration effort, this audit assumes a **specified stock + process
+ controlled scan** as the primary reference. That is a proposed target, not a
claim that one scan defines a stock universally. Keep physical density validation
as a separate gate. Familiar lab looks can subsequently be calibrated as named
Output Stages against their own references.

## Findings, ordered by action priority

### 1. Fix the colour grain reference coordinate — confirmed defect

[Renderer.swift](../../Sources/FilmEngine/Renderer.swift), `responseEntry`, samples
colour cubes at `0.18` to obtain `grayDensity`. For a logarithmically shaped cube,
middle gray instead lies at:

```text
(middleGrayLogExposure - minimumLogExposure)
/ (maximumLogExposure - minimumLogExposure)
```

The monochrome branch already applies `responseCoordinate`; the colour branch
does not. The resulting tiny reference value feeds `grain`'s
`0.5 / (gray - base)` scale. Both grain kernels in
[Pipeline.metal](../../Sources/FilmEngine/Metal/Pipeline.metal) clamp the resulting
response coordinate to 1, where shipped colour `densityResponse` tables are zero.

Reading the committed normal-development scan/viewing cubes gives:

| Profile | Correct middle-gray coordinate | Cached gray, red | Actual gray, red | Grain envelope at actual gray, all RGB |
| --- | ---: | ---: | ---: | --- |
| Portra 160 | 0.499756 | 0.003198 | 0.180024 | 0 / 0 / 0 |
| Portra 400 | 0.502439 | 0.002950 | 0.180291 | 0 / 0 / 0 |
| Provia 100F | 0.571429 | 0.001239 | 0.181937 | 0 / 0 / 0 |
| Velvia 50 | 0.548101 | 0.001038 | 0.180537 | 0 / 0 / 0 |
| Vision3 50D | 0.494548 | 0.003173 | 0.180363 | 0 / 0 / 0 |
| Vision3 200T | 0.529388 | 0.002306 | 0.180149 | 0 / 0 / 0 |
| Vision3 250D | 0.512245 | 0.006010 | 0.180434 | 0 / 0 / 0 |
| Vision3 500T | 0.492157 | 0.005336 | 0.180594 | 0 / 0 / 0 |
| CineStill 800T | 0.492157 | 0.005336 | 0.180594 | 0 / 0 / 0 |

Reproduce with `python3 docs/audits/film-stock-accuracy-probe.py`. This standard
library script reads float16 payloads and reproduces neutral-axis tetrahedral
interpolation and the envelope calculation. It does **not** execute Metal or
measure a photograph. Values describe middle-gray light entering Film Response,
with rating/WB/exposure effects neutralized; they are not a prediction for every
default UI setting. Print cubes and fractional Development Offsets need separate
runtime coverage.

**Next change:** shape the colour reference coordinate consistently. Add renderer
tests using shipped colour profiles and flat exposures around gray, checking
nonzero grain, envelope location and intensity scaling. Existing grain tests
primarily isolate the pass with identity cubes, so they miss this integration
error. Review golden-image changes on a Metal-capable Mac.

### 2. Establish independent photographic validation — confirmed coverage gap

[SpectralStepWedge.swift](../../ProfileBaker/SpectralStepWedge.swift) compares the
shipped scan/print output with the same `SpectralModel` that baked it. It uses
65 neutral coordinates and four chromatic coordinates per variant. The density
gate independently checks digitized neutral curves, which is valuable, but cannot
identify chromatic interlayer errors. The
[golden images](../golden-images.md) preserve existing 192 × 128 synthetic renders;
they contain no independent film reference.

**Impact:** a wrong scanner, shared dye model or implausible push model can pass
all those checks. Four coloured probes also provide limited numerical coverage
of a full cube; expanding them improves interpolation QA, not film validation.

**Next change:** create the held-out capture benchmark below. Keep source-density,
bake/interpolation, photographic match and spatial statistics as separately
reported results. Do not present the existing 0.03 linear-channel tolerance as a
perceptual colour-error limit.

### 3. Give CineStill a process-specific response — confirmed model limitation

[CineStill's authoring metadata](../../Curves/cinestill-800t/stock.json) changes
`process` to C-41 but derives colour payloads from Vision3 500T. The
[source note](../../Curves/cinestill-800t/SOURCES.md) explicitly acknowledges that
it models Remjet removal and not C-41 sensitometry. Manufacturer guidance states
that C-41 and ECN-2 produce different density/gamma; see the companion research.

The inherited cubes alone are therefore insufficient for a C-41 match. The
renderer also adds `log2(800/500) ≈ 0.678` stops through the artistic `trueISO`
assumption. That is a further calibration choice, not measured CineStill speed.
The source note's statement that rating at 800 is a push conflates exposure index
with changed development; normal C-41 at EI 800 should not be treated as a push
without a separate process change.

**Next change:** measure normal C-41 first, with separate ECN-2 references if
offered. Allow shared source data with explicit process-dependent sensitometry
instead of requiring byte-identical cubes. Replace cube equality tests with tests
for the intended shared and process-specific behavior.

### 4. Use published Vision3 dye and granularity measurements — available improvement

[Vision3 500T's sources](../../Curves/vision3-500t/SOURCES.md) already acknowledge
unused peak-normalized individual dye curves and diffuse RMS granularity curves.
[SpectralModel.swift](../../ProfileBaker/SpectralModel.swift) accepts isolated dyes
only for reversal; negative stocks partition aggregate absorption with Gaussian
lobes. Its comment that Kodak publishes no isolated dyes is too broad.

**Next change:** digitize the 5219 individual dye shapes and granularity nomograph,
record extraction uncertainty and retain the measured minimum/midscale curves as
constraints. Fit dye amplitudes under the appropriate measurement response;
normalized shapes alone do not provide absolute dye amounts. Add an authoring path
for density-dependent granularity instead of requiring one CSV row at density 1.
Extend to other Vision3 sheets only after checking their actual figures.

This reduces arbitrary parameters; it does not independently identify DIR or a
scanner. Portra publishes Print Grain Index in the cited sheets, so its artistic
RMS values must not be relabeled measured or obtained by an unsupported PGI-to-RMS
conversion.

### 5. Propagate grain through the output transform — confirmed architectural approximation

Measured colour cubes already return scan, print or viewing RGB. The renderer
then applies `value * 10^(-noise)`; it does not perturb film density and evaluate
the Output Stage again. Its envelope is likewise indexed by output RGB rather
than physical layer density. This contradicts a literal reading of the general
claim that all grain is added in Density Space before scanning.

For an Output Stage `F`, the desired operation is `F(D + δD)`. In general it is
not `F(D) * 10^(-δD)`. Even reversal transmission needs dye-channel mixing rather
than assuming film-layer noise is independent output-RGB attenuation. Negative
inversion and print-paper response introduce additional differences.

**Next change:** evaluate a density/dye-amount cube followed by a separate output
cube. A lower-cost alternative to investigate is an output Jacobian that propagates
small density fluctuations, with covariance and approximation error measured
against direct `F(D + δD)` evaluation. Fix finding 1 first so calibration is not
performed around the wrong envelope.

[Export.swift](../../Sources/FilmEngine/Export/Export.swift) also selects procedural
grain for Preview and thermally throttled Export, while regular Export may use
dye-cloud grain. Validate resampled spatial statistics across those paths; a
shared seed does not make different algorithms visually equivalent.

### 6. Calibrate the input and Output Stage before fitting stock colour — model limitation

[ImageDecoder.swift](../../Sources/FilmEngine/ImageDecoder.swift) disables several
RAW photographic enhancements, which is a good foundation. Its JPEG/other RGB
path converts an embedded colour profile into linear Rec.2020. That is a colour
space conversion, not recovery of the original scene exposure from a camera's
rendered photograph. Unknown tone curves, clipping and local processing remain.

[SpectralModel.swift](../../ProfileBaker/SpectralModel.swift) uses generic Gaussian
scanner channels centered at 650/550/450 nm with width 30, a tuned scan gamma,
gray auto-balance, a shoulder and final `[0,1]` clipping for negatives. These choices
can materially change the apparent stock. They are documented assumptions, not
calibration to a particular scanner.

**Next change:** benchmark controlled RAW intake separately from rendered-phone
photo intake. Specify camera conversion, exposure normalization and white balance.
Fit one locked scan/output pipeline first, then stock response. Do not silently
use per-image corrections to conceal model error. Treat negative gamut clipping
and HDR handling as measurable choices in the output contract.

### 7. Improve spectral and provenance limitations without overstating certainty

The reconstruction uses three smooth basis lobes over 400–700 nm. The colour
branch clamps negative reconstructed spectral power. The monochrome branch
analytically collapses the unclamped linear basis, so the two do not necessarily
choose the same spectrum for saturated inputs. RGB cannot uniquely determine a
spectrum; more wavelength bins alone cannot resolve that ambiguity.

[WhiteBalance.swift](../../Sources/FilmEngine/WhiteBalance.swift) applies a Bradford
transform from temperature/tint, while the Baker's observer uses D65 even for
tungsten stocks. This is an economical approximation to spectral illumination,
not a measured prediction for arbitrary LED, fluorescent or mixed lighting.

Two especially consequential borrowed inputs are marked `artistic`, so
`FilmProfile.isApproximation` does not disclose them through its approximation flag:

| Stock | Borrowed evidence | Present classification |
| --- | --- | --- |
| Vision3 250D | 50D sensitivity and dye-density CSVs | artistic |
| Velvia 50 | Provia dye-density CSV | artistic |
| CineStill 800T | Vision3 ECN-2 response for C-41 output | inherited measured inputs plus artistic parameters |

Fomapan 100, by contrast, flags its assumed sensitivity scale as `approximation`.
The catalogue contains 12 named stocks and five explicitly synthetic studies.
Its confidence labeling should distinguish measured inputs, borrowed inputs and
validation of the final look; a stock with measured curves is not automatically
a measured final emulation.

**Next change:** use measured reflectance/illuminant test spectra to quantify
reconstruction and clipping error before choosing a richer basis or illuminant
variants. Audit source classifications and expose confidence consistently. For
reversal, fit density through Status A measurement responses rather than treating
integrated density as dye peak amplitude. Do not invent a generic conversion
between “ECN-2 density” and Status M: ECN-2 names the process; verify the actual
measurement conditions first.

### 8. Calibrate secondary controls after baseline colour

- **B&W Contrast Filters:** the transmittances are logistic approximations.
  [The source note](../../Curves/contrast-filters/SOURCES.md) reports T-Max yellow
  overestimating the published factor by 0.63 stop and orange by 0.45 stop; the
  acceptance bound is 0.7 stop. Obtain measured transmittances, then reassess
  spectra and illuminants. A scalar daylight factor does not fully validate
  coloured-subject separation. These residuals are documented historical results,
  not a Metal validation rerun during this audit.
- **Development:** colour offsets change characteristic-curve slope/shadow loss
  using artistic parameters. Calibrate each process offset from separately
  developed material. B&W has one density curve and no variants, and the renderer
  forces its offset to zero; do not promise calibrated B&W push/pull behavior.
- **Reciprocity:** several stocks retain `[1,1,1]` above a published no-correction
  threshold. That means no simulated failure, not evidence that none exists.
  Fit exposure and colour corrections only over supported time ranges.
- **MTF:** colour metadata generally reduces published R/G/B MTF to green; runtime
  fits two Gaussian scales plus the original signal. Quantify fit residuals in
  cycles/mm at supported output pitches. Separate source-camera sharpening and
  scanner MTF from the added film response.
- **Halation/bloom:** the placement before Film Response is useful, but the
  strengths, threshold and radii are tuned. Measure point/edge profiles across
  exposure and wavelength; characterize lens flare independently. Retain creative
  boosts as creative behavior, outside the nominal-stock accuracy benchmark.

## A practical independent benchmark

Start with Portra 400, Vision3 500T and CineStill 800T: they exercise the existing
colour foundation, unused manufacturer data and a process distinction. Add Provia
100F and T-Max 100 before changing shared reversal or monochrome math.

1. **Lock the reference chain.** Record stock, batch/age/storage, format, lens,
   aperture, exposure, illumination, development chemistry/time/temperature and
   lab. Record scanner model, resolution, software/version, profile, inversion,
   sharpening, denoising and automatic corrections. Preserve linear positive
   transmission data where available, plus the specified finished scan.
2. **Capture paired material.** Photograph a characterized colour chart, neutral
   step wedge, skin/foliage/textiles and saturated objects with digital RAW and
   film under matched framing and measured exposure. Use a daylight source and
   tungsten source; record spectral power where possible. Add LEDs as a challenge
   set. Bracket initially at −2, −1, 0, +1, +2 stops; extend the wedge across the
   useful toe/shoulder. Exposure brackets are not development variants.
3. **Measure texture separately.** Capture uniform fields across density, slanted
   edges and bright points on dark backgrounds. Retain film dimensions and scan
   pitch. Repeat scans to estimate scanner noise and repeat film captures to
   estimate film/process variability. A single scan cannot separate both.
4. **Split before fitting.** Hold out whole scenes and rolls/development batches,
   not random patches from the same chart. Fit input normalization and the locked
   output chain, then neutral curves, chromatic response and finally spatial
   effects. Avoid jointly tuning all parameters from a few attractive photos.
5. **Report independent metrics.** Use density residuals in density units; tone
   error across exposure; CIEDE2000 median/95th percentile and patch errors under
   a fixed reference white/display transform; MTF residuals; grain variance,
   radial power spectrum and RGB covariance across densities; and halation
   radial profile/energy versus exposure. Compare corresponding patch interiors
   rather than pixelwise photographic error dominated by grain and alignment.
6. **Set acceptance from repeatability.** First measure scan/process variability.
   Require improvements on held-out rolls beyond that uncertainty, without
   worsening key skin/neutral/highlight subsets. Do not assign an arbitrary ΔE
   threshold and call it industry-standard film accuracy. Conduct blind visual
   comparisons at matched brightness/scale alongside the numerical results.

Minimum reference manifest fields: capture ID, split, stock/batch, process recipe,
EI, exposure/illumination, digital input conversion, scan configuration, frame
dimensions, patch/ROI definitions, file hashes and usage rights. Version the
manifest, fit parameters and benchmark outputs together.

## Suggested implementation sequence

| Order | Deliverable | Completion evidence |
| --- | --- | --- |
| 1 | Grain coordinate fix and confidence/source-note corrections | Shipped-profile renderer tests; reviewed golden changes; corrected provenance |
| 2 | Locked reference manifest and a first paired capture set | Repeatability report; independently scored held-out scans |
| 3 | Vision3 isolated dyes and density-dependent granularity | Reproducible extraction overlays; measurement-space residuals; held-out improvement |
| 4 | Process-specific CineStill response and density-aware output/grain | C-41/ECN-2 reference comparisons; grain propagation and preview/export checks |
| 5 | Spectral, development, B&W filter and spatial refinements | Per-feature ablations and held-out improvement beyond reference variability |

Steps 2 and 3 can proceed alongside the small first fix. The larger output/grain
change should be benchmarked as a prototype before committing to a runtime cost.
Increasing every cube to 65³ or adding more stocks should not displace these steps:
neither establishes whether the underlying model matches film.

## What was verified here

- Inspected the authoring metadata for all 17 Curve Sets and traced representative
  colour, reversal, monochrome, derived-stock, decode, output and spatial paths.
- Ran the read-only CPU probe against all nine shipped colour profiles with
  display-linear output; results above come from committed payload bytes.
- Reviewed numerical and golden-image test coverage and manufacturer-source notes.
- Added this audit, supporting probe and companion primary-source research only.

Swift is unavailable in this Linux workspace, and the renderer requires Apple
frameworks/Metal. No Swift tests, catalogue rebake, device render, datasheet
redigitization or photographic comparison was performed. The numerical grain
finding is supported by source and payload inspection; its visible impact and the
proposed fix still require the specified Mac renderer checks.
