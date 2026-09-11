# Dye

An iOS 17+ photo editor with a UI-free Swift 6 `FilmEngine` package. Shared domain
terms live in [CONTEXT.md](CONTEXT.md).

Open `FilmApp.xcodeproj`, choose the FilmApp scheme and an iOS simulator or device,
then run. Choose a photo using the system photo picker (no full-library permission
is required). For a device, select your signing team in Xcode.

## What the Catalogue is called, and what it claims

**The Catalogue ships under names of its own.** Twelve Profiles model Stocks whose
product names are live commercial trademarks, and shipping under those names is a
Guideline 5.2 exposure and a real takedown risk. `Curves/` and this file keep the
real spelling, because a Curve Set has to cite the datasheet its numbers came from.
The application does not:

| Curve Set | Display Name | Curve Set | Display Name |
| --- | --- | --- | --- |
| `portra-160` | Linen 160 | `provia-100f` | Meridian 100 |
| `portra-400` | Linen 400 | `velvia-50` | Vermilion 50 |
| `tri-x-400` | Newsprint 400 | `vision3-50d` | Daylight 50 |
| `t-max-100` | Graphite 100 | `vision3-200t` | Tungsten 200 |
| `cinestill-800t` | Halogen 800 | `vision3-250d` | Daylight 250 |
| `fomapan-100` | Ash 100 | `vision3-500t` | Tungsten 500 |

Profile **ids** are unchanged. They key saved Presets, Golden Image fixtures and the
CI Step Wedge patterns, and they are never shown. `Scripts/check-archive.py` fails
the build if a mark appears in a Display Name in the shipped Catalogue, or as a
string literal in the app binary that is not a lower-case identifier. That is a
guard against the obvious regression, not a proof. See `NOTICE.md`.

**Every Stock says what it is.** A name in the app carries a qualifier in front of
it. `Modelled` means built from published measurements and judgement, with no
photographic comparison against real film. `Approx.` means more: for at least one
parameter the manufacturer publishes no usable measurement, and a value borrowed
from a related Stock stands in. An unqualified name would mean a Stock checked
against held-out captures, and nothing in the Catalogue is that yet — so nothing
ships unqualified. `FilmProfile.qualifiedDisplayName` is the single source, and a
test fails when a new naming site reaches for the bare Display Name.

Tap **Film Stock** at the top of the editor to choose a stock. The picker then
shows the selected stock’s name. Choose **No Film Stock** in the browser to remove
the film response; this neutral profile uses the internal ID `identity`.

```sh
swift build
swift test
xcodebuild -project FilmApp.xcodeproj -scheme FilmApp -sdk iphonesimulator \
  -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO build
```

Tests run on macOS 14+ with a Metal device, without an iOS host app. Xcode and its
command-line tools are required. The package uses Swift 6 language mode and strict
concurrency; the renderer actor owns GPU state and keeps work off the UI actor.

The renderer's sole entry point accepts encoded photo bytes or linear Rec.2020
float16 pixels, a Profile and RenderSettings. ImageIO/Core Graphics honour the
input colour profile; CIRAWFilter handles RAW's camera colour matrix. Core Image
is confined to RAW decode. The ordered thirteen-pass Metal graph uses RGBA16Float
textures throughout. White Balance, Exposure, Bloom, Halation, MTF, Film Response
(tetrahedral Colour Cube sampling for colour, a Monochrome Collapse and Density
Curve for black & white), Grain, the Output Stage, the Adjustment Pass, Geometry
and the Display P3 output transform alter pixels; Reciprocity does too, for a Stock and an
exposure time that call for it, and is a pass-through everywhere else.
The canvas displays the tagged P3 result with Metal.

RenderSettings carry the user's controls in pipeline order. White Balance names
the Scene Illuminant by temperature and tint and adapts it toward the Stock
Balance with a Bradford von Kries scaling, so a daylight scene through a tungsten
Stock is blue and matching illuminants are an exact pass-through. Exposure is a
scalar multiply in linear light before the Film Response, and metering is at
**True Speed** rather than Box Speed where a profile records a difference.
Velvia's EI 40 assumption is artistic; CineStill uses its normal EI 800 without
an ancestry-based exposure adjustment. The Development Offset blends the two
nearest film-density cubes linearly and, as on a pushed roll,
rates the Stock faster: push +1 is −1 EV of exposure with the +1 curve shape.
Halation scatters above-threshold light back into the linear signal **before** the
Film Response, through a six-level float16 Scattering Pyramid whose per-channel
radii come from the Profile in Film-Plane Microns; its intensity control scales the
Stock's own strength on a 0–200% scale. Profiles without built-in halation use
an artistic fallback above 100%. See [the Halation Pass](docs/halation.md).
Bloom shares that pyramid and runs immediately before it, the order the light meets
them: it is the taking lens spreading a fraction of *all* the light across the
frame, neutral and unthresholded, and redistributing it rather than adding to it.
See [the Bloom Pass](docs/bloom.md).
Grain is applied in **Density Space**, after the Film Response and before the
Output Stage, as procedural value noise sized from `grainRadiusMicrons` through
Frame Width, amplitude-modulated by the Density Response and decorrelated across
channels; its own 0–200% control scales the Stock's published granularity, and a
seed fixes the field. See [the Grain Pass](docs/grain.md). The MTF Pass fits each
Stock's published response curve with two Gaussians before the Film Response, and
the Geometry Pass adds a vignette, gate weave and frame borders after the Output
Stage. See [the MTF and Geometry Passes](docs/mtf-and-geometry.md).
Spectral Profiles apply their log-exposure shaper at render time. New colour
profiles map exposure to film density, add grain in that domain, then apply a
separate scan, print or transparency-viewing cube. Scan and Print share developed
film payloads; `RenderSettings.outputStage` selects the observation.
`outputStage: .none` exposes a negative's Density Space for diagnostics. Reversal
Stocks use `none` for transparency viewing and cannot be inverted as negatives.
Foundation profiles retain their transmission-based scanner, and legacy fused
profiles remain readable. See [accuracy and validation](docs/accuracy-validation.md)
for the research, numerical checks and physical calibration still required.

Reciprocity Failure scales each layer separately by its own Schwarzschild
exponent once the frame is open longer than the Stock's threshold, before the
scattering Passes and the Film Response. The exposure-time control appears only
for a Stock whose Curve Set records a failure at all. See
[the reversal branch](docs/reversal.md), which is where the Pass earns its place.

The app decodes one screen-sized Preview through `Renderer.decode` and re-renders
it through a coalescing loop on every control change. Its controls are laid out
as three numbered stages so exposure and white balance visibly precede the film.

Photo bytes are the one input an attacker can influence, so decode bounds the source
from the file's header — which ImageIO parses without decoding a pixel — before
anything is allocated, on total pixel count as well as on each edge. Both Render
Paths apply the same limits, and the Preview subsamples during decode rather than
materialising the source raster and scaling it down. An oversized frame is an error
naming the size, not a process the system kills.

At default settings, Identity is bit-exact at the Working Space boundary for all finite float16 values,
including negative and HDR values; decoding and changing colour spaces inherently
rounds to float16. Untagged inputs are rejected instead of assuming sRGB. Tests also distinguish tetrahedral from trilinear interpolation
in all six tetrahedra and check tagged sRGB versus Display P3 input.

Export renders the frame at full resolution a **Tile** at a time, each carrying an
**Apron** sized to the furthest any Pass reaches, so a 48MP frame fits in memory
without a **Tile Seam** where a halo crosses a boundary. Grain is addressed in
image-global coordinates rather than Tile-local ones, so it does not repeat at the
Tile pitch. Export and Preview run identical shaders, and a tiled Export of a frame is
bit-identical to an untiled render of it. It reports progress and cancels per Tile,
runs on its own command queue, writes HEIF, JPEG or 16-bit TIFF tagged Display P3 or
sRGB, and gives up the Stock's Grain Model for the procedural one when the device is
thermally throttling. The colour half of the same look exports as a `.cube`
**Exported LUT**, rendered through the same shaders with the spatial Passes off and
labelled — in the file and in the UI — as carrying no grain, halation, bloom,
micro-contrast or vignette. See [the Export Render Path](docs/export.md).

The engine owns an **Exported File** rather than handing the app a temporary URL. An
exported frame is a full-resolution copy of the user's photograph, so it lives for
exactly as long as the user can still act on it: past the save to Photos, because the
share sheet needs it, and no further than the sheet offering that share. Releasing
the handle removes the file, and a launch sweep clears leftovers written by earlier
versions. The file carries the strongest file protection the platform offers.

RAW support uses the system decoder; synthetic DNG fixtures verify scene-linear
exposure ratios. Real camera fixtures and on-device memory and performance validation
are still needed: a simulator does not reproduce the memory pressure tiling exists for.

Profiles ship in the bundle and populate one flat horizontal filmstrip, with a
coloured process edge per cell and a legend above it — not, as this file used to
claim, a picker grouped by Process. The [container format](docs/profile-format.md)
documents schema, Provenance and lazy loading. The five synthetic studies are
intentionally not claims of stock accuracy, and now sit together at the end of the
browser rather than scattered through the middle of it.

The offline macOS `ProfileBaker` converts version-controlled CSV Curve Sets into
loadable Profiles and validates them through the renderer using numerical Step
Wedges. See [contributor instructions](Curves/README.md) to add a Stock, bake the
Catalogue, and inspect CSV/SVG validation reports. The Portra 400 and Portra 160 Curve Sets use an independent 31-band spectral model with
DIR interactions and four Development Offsets. Their measured density gates and
baked scan checks run in CI. See [the model and integration contract](docs/spectral-model.md)
and measurement sources and assumptions for [Portra 400](Curves/portra-400/SOURCES.md)
and [Portra 160](Curves/portra-160/SOURCES.md).
Kodak publishes Print Grain Index rather than RMS; RMS and unmeasured model
parameters are explicitly artistic.

Provia 100F and Velvia 50 are digitised from Fujifilm AF3-036E and AF3-0221E2 and
are the first reversal Stocks in the Catalogue. Fujifilm draws its charts as raster
plates rather than vector paths, so `Scripts/digitize-fujichrome.py` reads them from
ink pixels; Provia's colour charts arrive as one separation plate per curve and
Velvia's do not, which is why Velvia borrows Provia's isolated dye set and says so
in [its sources](Curves/velvia-50/SOURCES.md). Both publish a real diffuse RMS
granularity and a long-exposure compensation table, so Grain amplitude and the
per-layer Schwarzschild exponents are measured rather than assumed; Velvia's True
Speed of 40 against its Box Speed of 50 is not. See
[the reversal branch](docs/reversal.md).

Tri-X 400 and T-Max 100 add the **black & white branch**, which bypasses Colour
Cube sampling entirely: a Monochrome Collapse into one grey channel, then a
1024-entry Density Curve. Each Stock's **Spectral Weight** is integrated from its
digitised Kodak spectral sensitivity against the CIE colour matching functions
rather than assumed from a luminance weighting, so the two Stocks see
colour differently — Tri-X the bluer, T-Max the greener, by about 5 % of scan
value on a blue or a green subject at matched luminance. Both Stocks' rms
granularity is measured rather than artistic. **Contrast Filters** — yellow,
orange, red, green and blue — are a spectral multiply applied *before* the
collapse, so a red filter darkens blue sky and lightens brick instead of tinting
the frame, and each compensates its derived filter factor so the glass costs
separation and not exposure. They are offered for black & white Stocks alone.
Derived filter factors are checked against Kodak's published per-film tables in
CI. See [the black & white branch](docs/monochrome.md), and
[the Contrast Filters' sources](Curves/contrast-filters/SOURCES.md) for the measured
WRATTEN 2 transmission curves and remaining factor uncertainty.

The four Kodak **Vision3** motion picture stocks are the **ECN-2 branch**: 50D and
250D daylight-balanced at 5500 K, 200T and 500T tungsten at 3200 K, each digitised
from Kodak's own datasheet. A 5500 K scene through a tungsten Stock is heavily
blue, and the renderer leaves it that way — the film was made for another light,
and White Balance is where a photographer fixes it. All four are Remjet-backed, so
their modelled Halation is suppressed against a still colour negative's: 0.008 and
180/80/40 µm against Portra 400's 0.03 and 220/90/45. Cinestill 800T is
[derived from 500T](Curves/cinestill-800t/SOURCES.md) rather than modelled
separately — the same Emulsion without that backing, differing in Halation, Box
Speed and Process, at strength 0.55. Its Curve Set is 500T's; its Colour Cubes are
not byte-identical to 500T's, because it is baked at a 129³ lattice where every
other Stock is 65³. That is eight times the read, the decode and the texture upload
on every Stock switch and every Development Offset step. Nothing in
`Curves/cinestill-800t/` says why, and settling it is an accuracy question rather
than a performance one — see PERF-19 in `docs/audits/performance.md`.
Kodak's current 250D sheet draws its charts as raster plates rather than vector
paths, and [says so](Curves/vision3-250d/SOURCES.md) about the two it could not
separate.

Every colour negative now offers a **Print Output Stage** beside the Scan: an
optical enlargement onto RA-4 paper, digitised from Kodak E-4070, in place of the
scanner's inversion and auto-balance. What an enlarger and a sheet of paper do to
a negative is a spectral integral, baked into a separate density-to-output cube
per Development Offset. Grain perturbs the film before this observation. The
enlarger's dichroic filter pack and exposure are *solved* per offset so the Curve
Set's own reference neutral prints neutral, the way a lab prints each roll. The
result has a different tone response:
steeper through the midtones, several stops less shadow latitude, and highlights
that end at paper white instead of rolling off. **Scan stays the default**,
because most people's mental image of a Stock is a scan and a correct print reads
as wrong the first time. See [the ECN-2 branch and the Print](docs/print.md).

Portra 400, Portra 160, Cinestill 800T and the four Vision3 Stocks render in the app with
exposure, white balance, development, bloom, halation and grain controls, the
scan-or-print choice, and the vignette, gate weave and frame border of the
Geometry Pass. Bloom is the taking lens rather than the film, so every Stock
carries the same modelled one and both its parameters are artistic. Bloom and
Halation controls are available with every Stock and with No Film Stock (Identity);
profiles without built-in effects add them above 100%.

The editor saves Stock/settings **Presets** in SwiftData, offers hold-to-compare
and live photo thumbnails, and enables EDR on capable displays. Open **Contact
Sheet** in the toolbar to review every Profile against a fixed HDR reference.
Bit-exact renderer **Golden Images** guard the Catalogue; see the
[review and explicit update workflow](docs/golden-images.md).
