# Film stock accuracy: primary-source research

Research date: 2026-09-10. Scope: the colour emulation model, manufacturer measurements, and a practical independent validation programme. This is a research proposal, not a measured photographic accuracy report. **Verified** means supported by the linked manufacturer/standards source or the repository file; **inference/proposal** means our interpretation or suggested experiment. No physical film measurements were made.

## What “accurate” should mean

Choose a complete reference workflow: stock and batch, exposure, development, scanner or print/viewer, and final colour rendering. A manufacturer curve match, a neutral scan, and a lab scan match answer different questions. ICC distinguishes film rendering (negative measurements to a reproduction) from film unrendering (negative measurements to estimated scene values), and distinguishes colour rendering from colour-space conversion. [ICC glossary, pp. 1–3](https://www.color.org/ICC_white_paper5glossary.pdf).

**Repository evidence:** [spectral-model.md](../spectral-model.md) already correctly limits its 0.03 gates to published neutral-density reproduction and agreement between the baked cube and direct model. Those gates cannot independently validate the model's chromatic predictions, scanner, push/pull behaviour, or spatial effects.

**Proposal:** retain those numerical gates and add separately named measurements for film density, final rendered colour, and spatial appearance. Avoid a single “accuracy percentage.”

## Manufacturer evidence and its limits

| Source | Verified useful evidence | Limit and implication |
|---|---|---|
| [Kodak Portra 400 E-4050, pp. 3–4](https://imaging.kodakalaris.com/sites/default/files/files/resources/e4050_portra_400.pdf) | Status M characteristic curves, spectral sensitivity at a stated density/exposure, aggregate minimum/midscale dye densities, three MTF curves; PGI explicitly cannot be compared with RMS granularity. | Neutral characteristic curves do not identify three isolated dye spectra or a scanner. Keep the current Portra RMS assumption labelled artistic. |
| [Kodak Vision3 500T H-1-5219t, pp. 3–5](https://www.kodak.com/content/products-brochures/Film/VISION3-500T-Color-Negative-Film-7219-TECHNICAL-DATA.pdf) | Peak-normalized cyan, magenta and yellow dye curves in addition to aggregate spectra; an RGB RMS granularity nomograph measured with a 48 µm aperture; RGB MTF. The sheet says the data describe representative production under specified conditions, not every roll. | These are valuable constraints, not absolute dye concentrations or a complete stochastic grain model. The characteristic chart's “Densitometry: ECN-2” label is ambiguous. |
| [Fujifilm Provia 100F AF3-036E, pp. 3, 5–6](https://asset.fujifilm.com/master/emea/files/2020-10/2c27854d5609945fbe7e48afc61f815d/films_provia-100f_datasheet_01.pdf) | RMS 8 at density 1.0 above minimum with a 48 µm aperture; spectral sensitivities labelled Status A; a D50-derived viewing source is specified. | One RMS operating point cannot identify grain size, correlation, or density dependence. The spectral-sensitivity criterion differs from Portra's. The actual chart page is PDF page 6; repository source notes currently call it page 5. |
| [Fujifilm Velvia 50 AF3-0221E2, pp. 2, 7–8](https://asset.fujifilm.com/master/emea/files/2020-10/a71dda63e2662f012b3b74110794918a/films_velvia-50_datasheet_01.pdf) | Long-exposure corrections vary with time and include colour-compensating filters; the sheet describes the numbers as guidance and recommends actual-condition test exposures. | Fitting a reciprocity exponent from a correction table remains a model, including its treatment of filter transmission; it is not direct measurement of the exponent. |
| [CineStill 800T product information](https://cinestillfilm.com/products/800tungsten-c41-36exp-35mm-high-speed-color-negative-135) | C-41 produces higher density/gamma than ECN-2; the product recommends normal processing across EI 200–1000 and lists push processing separately. | A common underlying emulsion does not establish identical developed colour response. Rating at EI 800 alone is not evidence that the film was push processed. |

### 1. Use the Vision3 dye information already available

**Verified repository gap:** [500T dye-density.csv](../../Curves/vision3-500t/dye-density.csv) contains only `wavelengthNM,minimum,midscale`. [digitize-vision3.py](../../Scripts/digitize-vision3.py) selects only those two curves in its 500T specification and `vector_dye`. [SpectralModel.swift](../../ProfileBaker/SpectralModel.swift) accepts individual CMY tables only for reversal stocks; the negative branch partitions aggregate absorption with Gaussian weights. Its claim that Kodak publishes no isolated dyes is too broad. [500T SOURCES.md](../../Curves/vision3-500t/SOURCES.md) already acknowledges the unused individual curves.

**Proposal:** add independently specified dye-table kind, separate from negative/reversal process. Digitize the published CMY shapes alongside the existing base/aggregate curves. Fit amplitudes to the aggregate reference spectrum and validate predicted broadband densities; preserve extraction uncertainty. Do not blindly copy the reversal peak-wavelength amplitude solve, since a broadband density is not a monochromatic measurement. Start with 500T as a controlled comparison against the current Gaussian separation and then check each sibling's own sheet.

### 2. Give CineStill its own process response

**Verified repository gap:** [CineStill SOURCES.md](../../Curves/cinestill-800t/SOURCES.md) says its cubes are byte-identical to Vision3 500T and its model accounts only for remjet removal. CineStill's own comparison presents different C-41 and ECN-2 curves and colour separation. [CineStill Cs2 process comparison](https://cinestill.film/products/cs2-cine-simplified-ecn-2-bath-kit-low-contrast-motion-picture-color-negatives-for-ecp-scanning).

**Proposal:** retain shared parent data only as documented priors. Measure CineStill 800T in normal C-41 before introducing independent characteristic curves and interlayer parameters. Until then describe it as an approximate 800T interpretation. Remove the implication in the source notes that EI 800 necessarily means a push; separate exposure index from development treatment. The manufacturer comparison supports the direction of the difference, not an exact replacement LUT or a universal gamma adjustment.

### 3. Model the measurement instrument when fitting densities

ISO 5-3 defines spectral conditions and computational procedures for different standard density types. [ISO 5-3:2009 scope](https://www.iso.org/standard/52915.html). Kodak's ECN-2 process-control example explicitly uses **Status M**, distinguishing process from densitometry. [Kodak H-24 Module 1, figure 1-8](https://www.kodak.com/content/products-brochures/Film/Processing-KODAK-Motion-Picture-Films-Module-1.pdf).

**Inference:** the 5219 sheet's ECN-2 label is insufficient evidence for a novel density standard or conversion. Resolve its intended status with Kodak or another authoritative sheet before changing numbers. The Fuji Status A versus negative Status M distinction, meanwhile, is explicit in source metadata.

**Proposal:** use a forward instrument model when comparing spectral predictions to density measurements:

```text
D_channel = -log10( integral(W_channel(lambda) * T(lambda))
                   / integral(W_channel(lambda)) )
```

Here `W_channel` is the applicable instrument's complete spectral weighting, and `T` is film transmittance. Fit dye amounts jointly against these predicted measurements, including base density. Record the density status and optical geometry; do not relabel a density value to convert it. The equation is our modelling proposal, not a reproduction of unavailable ISO tables.

### 4. Distinguish spectrum uncertainty from numerical accuracy

Different spectral distributions can have identical tristimulus values; CIE defines such metameric pairs and describes mismatches after an illuminant/observer change. [CIE 080-1989 summary](https://www.cie.co.at/publications/special-metamerism-index-change-observer).

**Inference:** three input colour coordinates cannot uniquely determine the exposures of arbitrary film sensitivity curves. A smooth reconstruction is a prior. More wavelength samples improve integration of that prior but cannot recover lost spectral information. Narrowband LEDs, fluorescent materials and unusual pigments deserve their own stress set rather than an “all lighting” accuracy claim.

**Proposal:** test alternative reconstructed spectra against measured reflectance × measured illuminant spectra for held-out materials. Use measured spectra as an offline oracle, not as an assumption that normal input images contain spectra. Compare daylight and tungsten normalization explicitly. Preserve uncertainty flags for out-of-basis colours and clipping.

### 5. Separate scene-linear input from linearized rendered images

ACES describes its Output Transform as mapping scene-linear ACES into output-referred images for a display. ICC describes rendering as including tone/gamut mapping and preference adjustments. [ACES Output Transforms](https://docs.acescentral.com/system-components/output-transforms/), [ICC glossary, p. 2](https://www.color.org/ICC_white_paper5glossary.pdf).

**Inference:** converting a finished JPEG/HEIC into linear Rec.2020 does not by itself undo unknown camera tone curves, local contrast, clipping or preference rendering. A physical log-exposure model needs a stated interpretation of those values. An unknown clipped highlight is not recoverable through transfer-function decoding.

**Proposal:** establish accuracy first with a documented RAW-to-scene-linear path. Evaluate rendered-image inputs separately with an explicitly approximate exposure interpretation. Record the input transform and exposure normalization in every reference case.

### 6. Treat scanner, paper and viewing as calibrated components

An original scanner-characterization study fitted medium image-formation and scanner response, then evaluated independent spectrally similar materials. This supports a measurement-based scanner seam, without claiming its historical numerical result applies to our scanner. [Berns and Shyu, 1994, original paper abstract](https://library.imaging.org/cic/articles/2/1/art00011).

**Repository evidence:** [spectral-model.md](../spectral-model.md) calls its scanner generic; [print.md](../print.md) uses authored enlarger filters and a shared paper model. These remain hypotheses even if their LUTs reproduce their own forward code exactly.

**Proposal:** start with one fixed scan workflow, then add scanner-specific characterization if wanted. For reversal, test the viewer spectrum separately from chromatic adaptation and exposure normalization. Normalizing one neutral removes its cast; it does not generally cancel the illuminant's spectral effect on every coloured dye mixture. Treat the cancellation claim in [Provia source notes](../../Curves/provia-100f/SOURCES.md) as an oversimplification requiring an explicit D50/D65 comparison.

## A practical independent capture experiment

This is a proposed experimental design, not a manufacturer standard or work already performed.

1. **Pilot two stocks:** Portra 400 in normal C-41 and Vision3 500T in controlled ECN-2. Use documented fresh batches, then add CineStill 800T in C-41 as the first process-difference test. Keep stock/batch, chemistry, time, temperature, agitation, storage, elapsed time before development and scan settings in a manifest.
2. **Record repeatability:** expose duplicate neutral/colour targets on separate rolls and repeat scans. Use appropriate lab control strips and batch-adjusted reference readings to establish process stability. Kodak describes full control-curve comparison and batch/densitometer corrections; C-41 reference strips are provided for process monitoring. [Kodak H-24 Module 1](https://www.kodak.com/content/products-brochures/Film/Processing-KODAK-Motion-Picture-Films-Module-1.pdf), [Kodak Photo Systems C-41 control strips](https://kodak.photosys.com/products/color-negative-control-strips).
3. **Pair digital and film exposures:** use static targets, matching viewpoints and controlled light. Measure target spectra and illumination where possible; preserve RAWs with a documented scene-linear conversion. Include a neutral wedge, dense colour patches, skin-like targets, foliage, textiles, saturated pigments and ordinary scenes. Bracket, for example, −3 to +4 stops for the negative pilot; adapt the range for reversal. Record film-plane scale and camera/lens/filters.
4. **Separate observation levels:** retain density readings and selected transmission spectra before scan inversion. Save high-bit-depth scanner data with automatic exposure, colour, sharpening and grain reduction disabled when available. Freeze one inversion/output transform on the calibration set. A second operator-balanced lab scan can be a separate appearance target, never silently substituted for the measurement target.
5. **Capture spatial references:** flat fields at several densities for grain; repeated scans to estimate scanner noise; slanted edges or sine targets for MTF; isolated bright points/edges with spectral and exposure variation for halation. Separate lens flare from film effects with controlled optics and comparison exposures. Measure at film-plane units and preserve crop/magnification.
6. **Hold out whole captures:** fit on one set of scenes and rolls, validate on different scenes and a repeat roll. Hold out illuminants when testing generalization. Splitting neighbouring pixels from the same chart is not an independent validation split.

## Measurements and acceptance decisions

| Track | Proposed report | What it can establish |
|---|---|---|
| Density | Per-channel density residuals versus exposure, toe/midscale/shoulder residuals, repeat-roll intervals | Agreement with the developed-film response under recorded conditions |
| Final colour | Median, 95th percentile and worst-patch ΔE00 against the **film output**, grouped by illuminant/exposure; neutral L*/a*/b* errors | Agreement with the selected film + output workflow, not a claim that film matches the original scene |
| Grain | RMS in matched 48 µm aperture, density-dependent variance, spatial power spectrum and cross-channel covariance | Noise magnitude, scale and structure rather than a subjective “grain amount” |
| Sharpness | MTF versus cycles/mm, channel curves where available, edge overshoot | Spatial response with camera/scanner contributions documented |
| Halation | Per-channel radial/edge profiles versus exposure and film-plane distance | Halo colour, spread and threshold under the tested setup |
| Implementation | Existing density and cube/direct comparison gates | Extraction/baking/runtime consistency, kept separate from photographic validation |

Use a tested CIEDE2000 implementation and explicitly fix colour space, white/adaptation and viewing assumptions before calculating colour differences. The original implementation-notes authors supply test pairs and expected results. [Sharma, Wu and Dalal reference resources](https://hajim.rochester.edu/ece/sites/gsharma/ciede2000/).

**Proposal:** set final pass limits after measuring the reference workflow's repeatability. Require improvement on held-out captures with no material regression in designated skin/neutral groups. An arbitrary ΔE threshold or the existing 0.03 display-channel tolerance is not yet evidence of a photographic accuracy bound.

## Recommended order

1. Fix misleading evidence claims and define the RAW/reference scan contract.
2. Build the paired reference dataset and report baseline error before fitting.
3. Add measured Vision3 dye shapes and density-instrument fitting as separate ablations.
4. Fit stock/process-specific CineStill response and the chosen scanner workflow.
5. Fit grain/MTF/halation against spatial measurements, then measured push/pull and reciprocity variants.

No live renderer changes, profile rebakes, purchases or external lab requests were made by this research.
