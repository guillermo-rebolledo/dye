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
is confined to RAW decode. The ordered eleven-pass Metal graph uses RGBA16Float
textures throughout. White Balance, Exposure, Film Response (tetrahedral Colour
Cube sampling), Halation, the Scan Output Stage and the Display P3 output transform
alter pixels; Reciprocity, MTF, Grain and Geometry are explicit pass-throughs.
The canvas displays the tagged P3 result with Metal.

RenderSettings carry the user's controls in pipeline order. White Balance names
the Scene Illuminant by temperature and tint and adapts it toward the Stock
Balance with a Bradford von Kries scaling, so a daylight scene through a tungsten
Stock is blue and matching illuminants are an exact pass-through. Exposure is a
scalar multiply in linear light before the Film Response. The Development Offset
blends the two nearest baked Colour Cubes linearly and, as on a pushed roll,
rates the Stock faster: push +1 is −1 EV of exposure with the +1 curve shape.
Halation scatters above-threshold light back into the linear signal **before** the
Film Response, through a six-level float16 pyramid whose per-channel radii come
from the Profile in Film-Plane Microns; its intensity control scales the Stock's
own strength on a 0–200% scale. See [the Halation Pass](docs/halation.md).
Spectral Profiles apply their log-exposure shaper at render time; Density Space
Colour Cubes and Density Curves with a `scan` Output Stage are inverted through
transmission and auto-balanced so the Stock's mid-grey returns 0.18. Portra's
scan is baked into its cubes and is not inverted again. `outputStage: .none`
returns Density Space for diagnostics; Print is not implemented yet.

The app decodes one screen-sized Preview through `Renderer.decode` and re-renders
it through a coalescing loop on every control change. Its controls are laid out
as three numbered stages so exposure and white balance visibly precede the film.

Identity is bit-exact at the Working Space boundary for all finite float16 values,
including negative and HDR values; decoding and changing colour spaces inherently
rounds to float16. Untagged inputs are rejected instead of assuming sRGB. Tests also distinguish tetrahedral from trilinear interpolation
in all six tetrahedra and check tagged sRGB versus Display P3 input.

Full-resolution tiling, physical film effects and photo export belong to later
tickets. RAW support uses the system decoder; synthetic DNG fixtures verify scene-linear exposure ratios. Real camera fixtures
and on-device memory/performance validation are still needed.

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

Vision3 500T is digitised from Kodak H-1-5219t, and CineStill 800T is
[derived from it](Curves/cinestill-800t/SOURCES.md) rather than modelled
separately: the same Emulsion without its Remjet backing, so the two Profiles ship
byte-identical Colour Cubes and differ in Halation, Box Speed and Process. Both are
tungsten Stocks, so a daylight scene records blue and the renderer does not correct
it. Portra 400, Vision3 500T and CineStill 800T render in the app with exposure,
white balance, development and halation controls; Grain and MTF are still to come.
