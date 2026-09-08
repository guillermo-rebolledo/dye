# Dye

An iOS 17+ photo editor with a UI-free Swift 6 `FilmEngine` package. Shared domain
terms live in [CONTEXT.md](CONTEXT.md).

Open `FilmApp.xcodeproj`, choose the FilmApp scheme and an iOS simulator or device,
then run. Choose a photo using the system photo picker (no full-library permission
is required). For a device, select your signing team in Xcode.

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
is confined to RAW decode. The ordered twelve-pass Metal graph uses RGBA16Float
textures throughout. White Balance, Exposure, Bloom, Halation, MTF, Film Response
(tetrahedral Colour Cube sampling), Grain, the Scan Output Stage, Geometry and the
Display P3 output transform alter pixels; Reciprocity does too, for a Stock and an
exposure time that call for it, and is a pass-through everywhere else.
The canvas displays the tagged P3 result with Metal.

RenderSettings carry the user's controls in pipeline order. White Balance names
the Scene Illuminant by temperature and tint and adapts it toward the Stock
Balance with a Bradford von Kries scaling, so a daylight scene through a tungsten
Stock is blue and matching illuminants are an exact pass-through. Exposure is a
scalar multiply in linear light before the Film Response. The Development Offset
blends the two nearest baked Colour Cubes linearly and, as on a pushed roll,
rates the Stock faster: push +1 is −1 EV of exposure with the +1 curve shape.
Halation scatters above-threshold light back into the linear signal **before** the
Film Response, through a six-level float16 Scattering Pyramid whose per-channel
radii come from the Profile in Film-Plane Microns; its intensity control scales the
Stock's own strength on a 0–200% scale. See [the Halation Pass](docs/halation.md).
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
Spectral Profiles apply their log-exposure shaper at render time; Density Space
Colour Cubes and Density Curves with a `scan` Output Stage are inverted through
transmission and auto-balanced so the Stock's mid-grey returns 0.18. Portra's
scan is baked into its cubes and is not inverted again. `outputStage: .none`
returns Density Space for diagnostics; Print is not implemented yet. Reversal
Stocks use `none` for real rather than for diagnostics: their cubes carry the
transparency itself, so nothing inverts them and asking for a scan cannot.

Reciprocity Failure scales each layer separately by its own Schwarzschild
exponent once the frame is open longer than the Stock's threshold, before the
scattering Passes and the Film Response. The exposure-time control appears only
for a Stock whose Curve Set records a failure at all. See
[the reversal branch](docs/reversal.md), which is where the Pass earns its place.

The app decodes one screen-sized Preview through `Renderer.decode` and re-renders
it through a coalescing loop on every control change. Its controls are laid out
as three numbered stages so exposure and white balance visibly precede the film.

Identity is bit-exact at the Working Space boundary for all finite float16 values,
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

RAW support uses the system decoder; synthetic DNG fixtures verify scene-linear
exposure ratios. Real camera fixtures and on-device memory and performance validation
are still needed: a simulator does not reproduce the memory pressure tiling exists for.

Profiles now ship in the bundle and populate a picker grouped by Process. The
[container format](docs/profile-format.md) documents schema, Provenance and lazy
loading. The five synthetic studies are intentionally not claims of stock accuracy.

The offline macOS `ProfileBaker` converts version-controlled CSV Curve Sets into
loadable Profiles and validates them through the renderer using numerical Step
Wedges. See [contributor instructions](Curves/README.md) to add a Stock, bake the
Catalogue, and inspect CSV/SVG validation reports. The Portra 400 Curve Set now uses an independent 31-band spectral model with
DIR interactions and four Development Offsets. Its measured density gate and
baked scan checks run in CI. See [the model and integration contract](docs/spectral-model.md)
and [measurement sources and assumptions](Curves/portra-400/SOURCES.md).
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

Vision3 500T is digitised from Kodak H-1-5219t, and Cinestill 800T is
[derived from it](Curves/cinestill-800t/SOURCES.md) rather than modelled
separately: the same Emulsion without its Remjet backing, so the two Profiles ship
byte-identical Colour Cubes and differ in Halation, Box Speed and Process. Both are
tungsten Stocks, so a daylight scene records blue and the renderer does not correct
it. Portra 400, Vision3 500T and Cinestill 800T render in the app with exposure,
white balance, development, bloom, halation and grain controls, plus the vignette,
gate weave and frame border of the Geometry Pass. Bloom is the taking lens rather
than the film, so every Stock carries the same modelled one and both its parameters
are artistic.

The editor saves Stock/settings **Presets** in SwiftData, offers hold-to-compare
and live photo thumbnails, and enables EDR on capable displays. Open **Contact
Sheet** in the toolbar to review every Profile against a fixed HDR reference.
Bit-exact renderer **Golden Images** guard the Catalogue; see the
[review and explicit update workflow](docs/golden-images.md).
