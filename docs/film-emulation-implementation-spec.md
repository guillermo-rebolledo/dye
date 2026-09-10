# Dye film-emulation implementation specification

Repository reviewed at commit [`d65e61c`](https://github.com/guillermo-rebolledo/dye/tree/d65e61cfe9374401666e59d59db66b3ebc1405bf), 9 September 2026.

The subsequent [accuracy audit and implementation](accuracy-validation.md) supersedes
this baseline's cube architecture and CineStill calibration assumptions.

## Executive decision

Dye already implements the layered model the original proposal recommended. The film look is not represented by a flat collection of preset sliders: it is baked from measured or explicitly artistic film data into a `FilmProfile`, then rendered through a fixed physical pipeline. The 30-stock project should therefore be implemented primarily as a **catalogue and calibration expansion**, not as a renderer or preset-system rewrite.

Do not add profile fields such as `contrast`, `warmth`, `redResponse`, `highlightRolloff`, or `saturation`. In Dye those are *results* of the Characteristic Curves, spectral sensitivities, dye densities, development model, and chosen Output Stage. Authoring them again would create a second, conflicting source of truth.

For the requested scope:

- the existing runtime profile schema can represent all 30 stocks;
- the existing `RenderSettings` and SwiftData Preset model can save every current user-facing control;
- the current renderer already has the correct insertion points for tone, colour, grain, halation, bloom, exposure, and output rendering;
- 12 requested stocks are already shipped; 18 require new Curve Sets and baked profiles;
- the only plausible future schema extension is selectable scanner/lab renderings. It should be deferred until controlled reference scans demonstrate that one generic baked scan is insufficient.

## Current architecture

### Product boundaries

`Package.swift` defines a UI-free Swift 6 `FilmEngine` library and a macOS-only `ProfileBaker` executable; the iOS app consumes the library but does not ship the Baker ([source](https://github.com/guillermo-rebolledo/dye/blob/d65e61cfe9374401666e59d59db66b3ebc1405bf/Package.swift#L4-L14)).

The data flow is:

```text
manufacturer datasheets + explicit artistic assumptions
                         │
                         ▼
Curves/<stock-id>/stock.json + CSV/spectral inputs + SOURCES.md
                         │
                         ▼
              ProfileBaker (offline macOS)
                         │
                         ▼
Sources/FilmEngine/Catalogue/<stock-id>.filmprofile
                         │
                         ▼
        ProfileCatalogue → Renderer → Preview / Export / LUT
```

`ProfileCatalogue.bundled()` discovers every `.filmprofile` in the bundle, metadata-loads it, and rejects duplicate stable IDs; adding a correctly baked file therefore needs no hard-coded registry change ([source](https://github.com/guillermo-rebolledo/dye/blob/d65e61cfe9374401666e59d59db66b3ebc1405bf/Sources/FilmEngine/Profiles/ProfileCatalogue.swift#L3-L16)). Payloads are lazy-loaded and cached by content identity rather than display name ([profile source](https://github.com/guillermo-rebolledo/dye/blob/d65e61cfe9374401666e59d59db66b3ebc1405bf/Sources/FilmEngine/Profiles/Profile.swift#L3-L53)).

### Profile data model

`FilmProfile` already separates:

- identity and classification: `id`, `displayName`, `process`, `format`;
- exposure response: `nominalISO`, `trueISO`, `balance`, `reciprocity`;
- colour response: sparse `colour.lutVariants`, optional `inputShaper`, cube output contract, optional print cubes;
- monochrome response: spectral collapse weights, Density Curve, and Contrast Filter weights;
- image structure: `grain`, `mtf`;
- scattering: `bloom`, `halation`;
- lineage: `derivedFrom`;
- evidence quality: dotted-path `provenance` values of `measured`, `artistic`, or `approximation`.

See the concrete Swift schema in [`FilmProfile.swift`](https://github.com/guillermo-rebolledo/dye/blob/d65e61cfe9374401666e59d59db66b3ebc1405bf/Sources/FilmEngine/Profiles/FilmProfile.swift#L1-L255) and its authoring/container contract in [`docs/profile-format.md`](https://github.com/guillermo-rebolledo/dye/blob/d65e61cfe9374401666e59d59db66b3ebc1405bf/docs/profile-format.md).

The binary `.filmprofile` container carries a validated JSON header and named float16 payloads. Colour stocks use 33³ cubes, with 65³ available for rapidly turning responses such as Velvia; black-and-white stocks use a 1,024-entry float16 Density Curve. This is already adequate for the requested stocks.

### Preset model

A user Preset is deliberately separate from a Stock Profile. SwiftData stores only `name`, stable `stockID`, encoded `RenderSettings`, and `createdAt` ([source](https://github.com/guillermo-rebolledo/dye/blob/d65e61cfe9374401666e59d59db66b3ebc1405bf/FilmApp/PresetSheet.swift#L5-L16)). Applying a Preset validates its settings and resolves the stock through the current Catalogue; missing stocks produce an explicit error rather than silently substituting another ([source](https://github.com/guillermo-rebolledo/dye/blob/d65e61cfe9374401666e59d59db66b3ebc1405bf/FilmApp/EditorModel.swift#L393-L405)).

`RenderSettings` is Codable and already preserves output encoding, Scene Illuminant, tint, exposure, exposure time, Development Offset, monochrome Contrast Filter, bloom/halation/grain intensity, geometry, Adjustments, seed, and Output Stage ([source](https://github.com/guillermo-rebolledo/dye/blob/d65e61cfe9374401666e59d59db66b3ebc1405bf/Sources/FilmEngine/RenderTypes.swift#L40-L190)). Newer optional settings decode to neutral defaults, establishing the migration pattern to follow if another setting is ever added.

No Preset schema change is required for catalogue expansion. Do not copy physical Profile parameters into Presets; Presets should continue to reference a Stock and store user overrides only.

### Image-processing pipeline

The renderer operates in linear Rec.2020 using RGBA16Float intermediates. Its fixed 13-pass order is ([source](https://github.com/guillermo-rebolledo/dye/blob/d65e61cfe9374401666e59d59db66b3ebc1405bf/Sources/FilmEngine/Renderer.swift#L897-L903)):

```text
Decode
→ White Balance
→ Exposure
→ Reciprocity
→ Bloom
→ Halation
→ MTF
→ Film Response
→ Grain
→ Output Stage
→ Adjust
→ Geometry
→ Output Transform
```

This ordering is already correct for the proposed model: exposure-domain phenomena precede the film response; grain is in Density Space; scanning/printing follows the negative; editor adjustments operate on the positive; geometry is not baked into the stock.

Preview and full-resolution tiled Export use the same graph. Spatial parameters convert from Film-Plane Microns through the stock format and full Frame Width, while global grain coordinates and export aprons prevent resolution drift and tile seams. Exported `.cube` LUTs intentionally omit the spatial half of the look.

## Mapping film characteristics onto Dye

| Film characteristic | Existing representation | Authoring/calibration rule | Runtime/API consequence |
| --- | --- | --- | --- |
| Toe, midtone slope, shoulder, latitude | Per-layer Characteristic Curves in the Curve Set; baked Colour Cubes or B&W Density Curve; `colour.inputShaper` maps scene-linear values to physical log exposure | Digitise manufacturer D-logE curves. Keep density and physical log exposure; do not reduce to contrast/black-point sliders. Use 65³ only when the step-wedge error justifies it. | No change. `filmResponse` already applies the log shaper and tetrahedral cube interpolation; B&W uses its own collapse/curve shader. |
| Hue and colour response | Spectral sensitivity, dye-density data, observer, spectral reconstruction, DIR/development assumptions, baked 3D cube | Calibrate skin, foliage, sky, primaries, and mixed light against controlled references after the numerical gate passes. Never encode “Kodak orange” or “Fuji green” as a global cast. | No change. The cube is the correct combined representation of non-separable channel response. |
| Saturation and luminance-dependent colour | Emergent from the spectral/baked cube; optional post-output `Adjustments.saturation` and `vibrance` are user edits | Tune the spectral model and scan/print transform for stock identity. Keep user Saturation/Vibrance neutral in reference renders. | No new stock fields. Do not use Adjustments to compensate for a wrong stock profile. |
| Grain amount | `grain.rmsGranularity`, scaled from the standard 48 µm aperture by Selwyn’s law | Use published diffuse RMS where available. If only Print Grain Index or no compatible measurement exists, mark the value `artistic` or `approximation`. | No change. `grainIntensity` remains a 0–200% user scale around the stock’s 100% value. |
| Grain shape and size | `GrainModel`, `grainRadiusMicrons`, 32-point `densityResponse`, channel correlation and per-channel radius scale | Silver stocks: `stochastic`; chromogenic colour and XP2: `dye-cloud`; tune density dependence from matched scans, never by adding uniform output noise. | No change. Density-space application is already in the right pass. Note that Preview currently resolves every model to procedural while Export can use `dye-cloud`; visual calibration of model-specific texture must use Export. |
| Halation | `strength`, threshold, RGB radius in Film-Plane Microns, tint; pre-response scattering pyramid | Remjet-backed Vision3 should remain weak; CineStill should be strong and red-dominant. Treat values as artistic unless a defensible measurement exists. Calibrate with point lights and bright edges at multiple output sizes. | No change. Keep halation out of the Colour Cube and post-output Adjustments. |
| Bloom | Neutral, unthresholded lens diffusion with strength and radius | Because this is lens behavior, keep the common baseline or set it to zero during stock matching. Do not use per-stock bloom to force a film signature. | No change. The UI may retain the creative control, but stock acceptance images should include a bloom-off comparison. |
| Acutance/micro-contrast | Published MTF samples, fitted at runtime to direct + two Gaussian components | Digitise a published MTF where possible. Where only resolving power exists, mark the derived MTF artistic. | No change. Do not counterfeit sharpness with the post-output Contrast control. |
| Box-speed versus practical metering | `nominalISO`, `trueISO`; gain includes `log2(nominalISO / trueISO)` | Keep both values evidence-tagged. Use true speed only where the datasheet or a documented calibration supports it; otherwise default to box speed and mark the decision honestly. | No change. Existing gain planning handles rating and Development Offset together ([source](https://github.com/guillermo-rebolledo/dye/blob/d65e61cfe9374401666e59d59db66b3ebc1405bf/Sources/FilmEngine/Renderer.swift#L354-L380)). |
| Push/pull behavior | Sparse Development Offset variants; renderer clamps and linearly blends neighboring variants while changing rating by the same stop amount | Bake only offsets supported by a manufacturer processing range or a documented artistic model. Do not emulate development with Exposure or post Contrast. | No change for colour. B&W currently has one Density Curve and no development variants; only extend this if pushed B&W is an explicit product requirement. |
| Reciprocity failure | Threshold seconds plus one Schwarzschild exponent per colour layer | Fit published compensation tables; mark unsupported long-exposure behavior artistic. For monochrome use equal channels. | No change. The control already appears only when the Profile is non-silent. |
| Scene illuminant / tungsten-daylight balance | Profile `balance`; `RenderSettings.temperatureKelvin` and tint; Bradford adaptation before film | Preserve the real daylight/tungsten mismatch. A daylight scene through 500T should be blue until the user identifies/corrects the Scene Illuminant. | No change. Avoid baking a daylight correction into 200T/500T/CineStill cubes. |
| Scanner/output rendering | Negative scan is baked into spectral scan cubes or performed by runtime inversion for foundation profiles; optional baked RA-4 print cubes; E-6 is a transparency (`none`) | Define one named baseline scan policy for v1 and keep it identical across stock calibration. Treat Frontier/Noritsu/lab corrections as output renderings, not emulsion. | Existing `OutputStage.scan/print/none` is sufficient for one canonical scan. Selectable scanner looks require the deferred extension below. |
| Exposure brackets | `exposureStops` before response plus physical shaper/true-speed/development behavior | Validate −2, −1, 0, +1, +2 EV on the same scene. The expected result is not a uniform brightness change: toe, shoulder, colour crossover, and grain visibility should change through the existing pipeline. | No change. |

## Requested catalogue status

### Already implemented — retain and recalibrate rather than replace

| Requested stock | Current Profile ID | Notes |
| --- | --- | --- |
| Kodak Portra 160 | `portra-160` | Measured spectral Curve Set; four scan and four print offsets. |
| Kodak Portra 400 | `portra-400` | Measured spectral Curve Set; four scan and four print offsets. |
| CineStill 800T | `cinestill-800t` | Derived from `vision3-500t`; different process, rating, and halation, but byte-identical colour cubes. Known limitation described below. |
| Fujifilm Velvia 50 | `velvia-50` | E-6 transparency; 65³ cube; measured RMS and reciprocity inputs. |
| Fujifilm Provia 100F | `provia-100f` | E-6 transparency; four offsets. |
| Kodak Tri-X 400 | `tri-x-400` | B&W spectral collapse, Density Curve, measured filter factors. |
| Kodak T-Max 100 | `t-max-100` | B&W spectral collapse, Density Curve, measured filter factors. |
| Fomapan 100 | `fomapan-100` | Explicitly labelled Approximation because the source spectrogram lacks a vertical scale. |
| Kodak Vision3 50D | `vision3-50d` | ECN-2 daylight; scan and print variants. |
| Kodak Vision3 250D | `vision3-250d` | ECN-2 daylight; scan and print variants. |
| Kodak Vision3 200T | `vision3-200t` | ECN-2 tungsten; scan and print variants. |
| Kodak Vision3 500T | `vision3-500t` | ECN-2 tungsten; scan and print variants; parent of CineStill. |

The current authoring inventory can be seen directly under [`Curves/`](https://github.com/guillermo-rebolledo/dye/tree/d65e61cfe9374401666e59d59db66b3ebc1405bf/Curves), with their baked counterparts under [`Sources/FilmEngine/Catalogue/`](https://github.com/guillermo-rebolledo/dye/tree/d65e61cfe9374401666e59d59db66b3ebc1405bf/Sources/FilmEngine/Catalogue).

### Missing — 18 new Curve Sets

| Process | Stock IDs to add | Count | Closest implementation template |
| --- | --- | ---: | --- |
| C-41 | `portra-800`, `gold-200`, `ultramax-400`, `ektar-100`, `colorplus-200`, `fujicolor-c200`, `fujifilm-400` | 7 | Portra for Kodak spectral negatives; use a same-process spectral model but never copy its measured curves. |
| E-6 | `velvia-100`, `ektachrome-e100` | 2 | Provia/Velvia reversal branch. Start at 33³ and move to 65³ only if validation fails or perceptual gradients visibly break. |
| B&W silver | `hp5-plus-400`, `fp4-plus-125`, `delta-3200`, `t-max-p3200`, `kentmere-100`, `kentmere-400`, `fomapan-200`, `fomapan-400` | 8 | Tri-X/T-Max/Fomapan B&W path, with each stock’s own sensitivity and Density Curve. |
| B&W chromogenic | `xp2-super` | 1 | B&W collapse/curve with process `bw-chromogenic` and Grain Model `dye-cloud`. |

The four Vision3 stocks are complete. “Fomapan 100/200/400” expands to three Profiles, of which 100 already exists.

### Per-stock qualitative acceptance targets

These are perceptual checks, not replacement schema fields.

- **Portra 800:** Portra-family skin and shoulder, more visible grain and low-light colour instability than 160/400.
- **Gold 200:** warmer yellow/orange relationship and stronger consumer-film contrast than Portra, without Ektar-level separation.
- **UltraMax 400:** punchier contrast/saturation and coarser structure than Portra 400.
- **Ektar 100:** very fine grain, strong acutance, high saturation, pronounced separation in red/blue/green/cyan; skin must remain scanner-dependent rather than universally red.
- **ColorPlus 200:** moderate grain, restrained snapshot contrast, mild warmth; no artificial faded-black “vintage” overlay.
- **Fujicolor C200 / Fujifilm 400:** natural skin and neutral greys first; cooler blue/green relationships may emerge from the measured spectral model, not from a blanket green cast.
- **Velvia 100:** high saturation/contrast with strong red-yellow-orange response; distinguish it from Velvia 50 by more than speed and grain.
- **Ektachrome E100:** neutral E-6 rendering, fine grain, natural skin, moderate saturation, and a hard reversal-film highlight endpoint distinct from Provia.
- **HP5 Plus 400:** broad midtones and shadow latitude with visible classic grain; box-speed must not look like a heavily pushed social-media preset.
- **FP4 Plus 125:** fine grain, smooth midtones, high detail, moderate contrast.
- **Delta 3200:** broad available-light tonality with large grain; document the chosen EI/developer because “3200” is not a single visual condition.
- **T-Max P3200:** high-speed T-grain structure that stays cleaner/more defined than enlarged HP5 grain; document EI/development.
- **Kentmere 100/400:** neutral, forgiving traditional rendering; 400 visibly grainier and softer than 100.
- **Fomapan 200/400:** progressively more traditional/coarse structure; avoid inventing halation to create “old film.”
- **XP2 Super:** chromogenic, fine and smooth with broad latitude; must not be implemented as HP5 with saturation set to zero.

## Authoring contract for each new stock

Create `Curves/<stock-id>/` using the same-process measured stock as the structural template. Each addition must contain:

1. **`SOURCES.md`** — manufacturer, exact document edition, page/figure, source URL, local source checksum, extraction method, units, assumptions, licensing, and every gap that forces `artistic` or `approximation` provenance.
2. **`stock.json`** — complete metadata. Stable ID is lowercase kebab case; Display Name is the only presentation name. Start with 135-format calibration so grain scale has one defined physical baseline.
3. **Colour negative/E-6 data** — normal red/green/blue Characteristic Curves, sensitivity, dye density, observer, MTF, granularity, and `spectral.json`. Generate non-neutral Development Offsets through the documented model unless the manufacturer publishes separate curves.
4. **B&W data** — one Density Curve, sensitivity, observer, MTF, granularity, and only the manufacturer’s own filter-factor table when one exists. The Baker derives spectral and Contrast Filter weights; never author them in `stock.json`.
5. **Provenance** — every required dotted physical path marked independently. If any parameter substitutes for missing evidence, use `approximation`; the UI already surfaces that status.
6. **Baked output** — run `Scripts/bake-catalogue.sh`; commit both authoring sources and the deterministic `.filmprofile`.

The repository’s full contribution contract and commands are in [`Curves/README.md`](https://github.com/guillermo-rebolledo/dye/blob/d65e61cfe9374401666e59d59db66b3ebc1405bf/Curves/README.md). New stock discovery is automatic.

## Calibration and reference library

The existing Contact Sheet and Golden Images are excellent renderer-regression tools, but they do not prove likeness to real film. Golden Images are intentionally bit-exact snapshots of the current engine, and the synthetic Contact Sheet checks ramps, colour patches, HDR highlights, detail, grain, and framing ([source](https://github.com/guillermo-rebolledo/dye/blob/d65e61cfe9374401666e59d59db66b3ebc1405bf/docs/golden-images.md)). Add a separate **perceptual calibration corpus** rather than changing what goldens mean.

Recommended repository layout:

```text
References/
  README.md
  manifests/
    portra-400.json
    ...
  thumbnails/                 # small, redistributable review derivatives only
  reports/                    # generated comparison metrics/contact sheets
```

Keep large originals in a versioned external artifact store or Git LFS only when redistribution rights permit it. Commit the manifests even when images cannot be committed.

Proposed offline manifest schema:

```json
{
  "schemaVersion": 1,
  "stockID": "portra-400",
  "format": "135",
  "development": {
    "process": "C-41",
    "lab": "documented lab name",
    "developer": "if known",
    "developmentOffset": 0
  },
  "rendering": {
    "kind": "scan",
    "device": "scanner/model or camera-scan setup",
    "operatorCorrections": "neutral-only",
    "outputProfile": "embedded ICC/profile name"
  },
  "captures": [
    {
      "sceneID": "daylight-portrait-01",
      "category": "skin-daylight",
      "exposureOffsetEV": 0,
      "illuminantKelvin": 5500,
      "referenceFile": "artifact://...",
      "digitalInputFile": "artifact://...",
      "rights": "owner/licence/restrictions",
      "sha256": "..."
    }
  ]
}
```

Required scene matrix per stock:

- daylight and open-shade skin;
- sky/clouds and dense foliage;
- controlled neutral/colour chart plus saturated red, yellow, green, cyan, blue, magenta objects;
- high-contrast sun, golden hour, tungsten/mixed light;
- night/neon/specular point lights;
- exposure brackets at −2, −1, 0, +1, +2 EV;
- for reciprocity stocks, matched short and long exposures;
- one consistent 35 mm scan path for grain comparisons.

For each calibration revision, render with Adjustments neutral and create two views: spatial effects at stock defaults, and bloom/halation/grain off to isolate tone/colour. Evaluate neutral ΔE, hue-angle error by patch, ramp derivative/toe/shoulder, clipped-channel onset, grain power/amplitude by density band, halo radial falloff, and MTF/acutance. Metrics should guide diagnosis, not replace side-by-side human review.

## Scanner/output policy and deferred extension

### Version 1 policy: no schema change

Today a spectral negative’s canonical scan is baked into its Colour Cubes, a print uses a second cube set, and E-6 carries the transparency itself. This is internally coherent and should remain the first milestone.

Define and document one canonical scan baseline in `docs/scan.md`:

- scanner spectral-response assumption or named physical capture path;
- auto-balance/reference-neutral rule;
- gamma/shoulder behavior;
- whether operator corrections are prohibited or normalized;
- embedded output profile;
- calibration target and version.

Then ensure every stock’s `SOURCES.md` names that baseline. This makes stock comparisons meaningful while avoiding a premature UI/API expansion.

Make the baseline a shared Baker input rather than leaving its scanner channels hard-coded and its transfer partly in each stock's `scanGamma`:

```text
Curves/reference-scan/
  scan.json
  sensitivity.csv       # when measured channel curves exist
  SOURCES.md
```

Add optional `FilmProfile.Colour.scanModelID: String?`. Newly baked spectral negatives should name `dye-reference-scan-v1`; nil preserves existing containers as `legacy-generic-scan`. Include every consumed scan-model file in `sourceFingerprint`. This is an additive metadata/authoring change only: it does not add a Metal pass, a `RenderSettings` control, or a new pixel payload. It is justified because two stock cubes cannot be compared meaningfully if their scan baseline is implicit or independently tuned.

### Add selectable scanner/lab renderings only after evidence

If the controlled corpus proves that Frontier, Noritsu, camera-scan, or distinct lab policies must be first-class choices, do not add a post-filter. Bake each stock × development × rendering combination because scanner response interacts with the negative’s dye densities.

A backward-compatible profile extension can be:

```swift
struct FilmProfile.Colour {
    var lutVariants: [Variant]                 // retained: canonical scan / E-6
    var printVariants: [Variant]?              // retained
    var scanRenderings: [ScanRendering]?       // new, optional
}

struct ScanRendering: Codable, Equatable, Sendable {
    var id: String                             // e.g. "generic-v1", "frontier-sp3000-v1"
    var displayName: String
    var variants: [Variant]                    // same Development Offsets as lutVariants
}

struct RenderSettings {
    var scanRenderingID: String?               // new, optional; nil = canonical lutVariants
}
```

Validation rules:

- allowed only when `colour.outputStage == .scan` and the Process is negative;
- IDs unique and stable;
- each rendering covers exactly the canonical Development Offsets;
- payload names are disjoint;
- `scanRenderingID` is ignored/reset when Output Stage is print or the film itself;
- missing or unknown IDs fail explicitly when applying a Preset—never silently change the look;
- add provenance for each rendering’s scanner model and calibration inputs;
- include rendering assets in the source fingerprint and lazy payload cache.

This adds no render pass: `Renderer.plan` selects a different cube set at the same place it currently selects scan versus print. Add an optional decoder default (`nil`) to preserve old Presets. The app then exposes the choice in Lab only when a Profile has more than one scan rendering.

### Optional Preset calibration disclosure

Catalogue expansion itself needs no Preset migration. If Presets are expected to reproduce a look across future profile recalibrations, add `profileFingerprint: String?` to the SwiftData `Preset`. Save the selected Profile's `colour.sourceFingerprint`; on apply, nil means a legacy Preset, a match is silent, and a mismatch applies the current Profile while showing a non-blocking “Stock calibration updated” notice. Do not persist cubes or physical profile fields in SwiftData. Treat this as a product/reproducibility enhancement, not a prerequisite for adding the 18 stocks.

## Known modelling gaps

1. **CineStill 800T is intentionally narrow today.** Its profile derives from Vision3 500T and shares byte-identical colour cubes; only process label, box/true speed, and halation differ. The repository itself records that C-41 versus ECN-2 sensitometry is not modeled ([source](https://github.com/guillermo-rebolledo/dye/blob/d65e61cfe9374401666e59d59db66b3ebc1405bf/Curves/cinestill-800t/SOURCES.md)). Do not hide this with Adjustments. First obtain a controlled C-41 calibration. If the difference is material, either convert CineStill to a full independent Curve Set while keeping lineage as documentation, or add a narrowly scoped bake-time process transform. Do not add a runtime “CineStill contrast” slider.
2. **B&W Development Offsets are not modeled.** A B&W Profile has one Density Curve. That is sufficient for the requested box-speed stock catalogue; pushed HP5/Delta/P3200 looks should become a separate follow-up with one density payload per offset and matching developer metadata, not ad hoc post Contrast.
3. **A generic scan is not a commercial-scanner emulation.** The existing spectral model explicitly describes broad synthetic scanner channels and artistic transfer behavior. Catalogue claims and UI copy should say “canonical scan” until a physical scanner is calibrated.
4. **Grain validation differs between Preview and Export.** Preview always uses procedural grain; the declared `dye-cloud` model is selected on Export. Texture acceptance must include exported full-resolution crops.
5. **A passing numerical bake is not perceptual proof.** Step wedges bound interpolation against the same source/model. The independent controlled corpus is the gate for likeness.

## Verification and acceptance gates

Every new stock must pass, in order:

1. `FilmProfile.validate()` including complete provenance and process invariants.
2. Deterministic `ProfileBaker bake` and source fingerprint validation.
3. Step-wedge error within the documented stock-specific tolerance; use the repository’s 0.03 default unless the source quality justifies a stricter or explicitly documented looser bound.
4. Process-level tests: colour-cube variants, E-6 no-inversion, B&W spectral collapse/filter behavior, negative scan/print behavior as applicable.
5. New catalogue Golden Image, reviewed through the Contact Sheet before explicitly recording it.
6. Perceptual corpus comparison for every required scene/exposure category, with neutral Adjustments and a spatial-off isolation render.
7. Preview performance and full-resolution tiled Export, including seam checks around bright points and grain continuity.
8. Preset round-trip: save, relaunch, apply, stock/settings restored; unavailable stock and any future missing scan rendering fail explicitly.

The existing tests already cover interpolation, colour-managed decode, true-speed metering, development blending, scan inversion, scattering placement, grain density-space placement, MTF, monochrome spectral response, print versus scan, export tiling, preset-compatible settings decoding, and bit-exact catalogue goldens. Extend those fixtures rather than inventing a parallel test harness.

## Recommended implementation sequence

### Phase 0 — baseline and naming

- Add `docs/scan.md` defining the canonical scan policy.
- Add the offline reference manifest schema and one fully licensed pilot set.
- Freeze a calibration protocol: 135 format, processing, scan settings, output profile, scene matrix, bracket convention.
- Keep all Adjustments neutral while tuning Profiles.

### Phase 1 — representative pilot stocks

Implement one missing stock per difficult branch:

1. `ektar-100` — fine-grain, high-separation C-41 stress case.
2. `ektachrome-e100` — neutral E-6 comparison against Provia/Velvia.
3. `hp5-plus-400` — Harman B&W where filter-factor evidence may be absent.
4. `xp2-super` — chromogenic B&W/dye-cloud stress case.

Use what these reveal to refine authoring scripts and the reference report, not the runtime profile model.

### Phase 2 — family expansion

- Kodak C-41: Portra 800, Gold 200, UltraMax 400, ColorPlus 200.
- Fuji colour: Fujicolor C200, Fujifilm 400, Velvia 100.
- Fine/fast B&W pairs: FP4/HP5, Delta 3200/P3200, Kentmere 100/400, Fomapan 200/400.

Batch by manufacturer/datasheet layout so digitisation scripts are reusable, but review each Profile independently.

### Phase 3 — perceptual calibration and release

- Calibrate the 30-stock set against the controlled corpus.
- Run full tests and regenerate only intentionally changed/new goldens.
- Review stock differentiation on the same input: Portra 160/400/800; Velvia 50/100 vs Provia/E100; HP5 vs Tri-X vs T-Max; Vision3 500T vs CineStill 800T.
- Ship the canonical scan first.
- Decide on selectable scanner renderings only from the resulting evidence; if adopted, implement the optional extension above without adding a render pass.

## Definition of done

The work is complete when every requested stock has a traceable Curve Set and baked Profile; every measured/artistic/approximate claim is explicit; numerical and renderer regressions pass; the stock remains recognizable across the shared scene/exposure matrix; grain and halation are physically scaled across Preview and Export; Output Stage semantics remain honest; and a saved user Preset references the stable Stock ID plus controls without duplicating the Profile’s physical data.
