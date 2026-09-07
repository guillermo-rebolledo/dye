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
textures throughout. Only Film Response (tetrahedral Colour Cube sampling) and the
Display P3 output transform alter pixels at this stage; future physical passes
are explicit pass-throughs. The canvas displays the tagged P3 result with Metal.

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
Catalogue, and inspect CSV/SVG validation reports. No third-party simulation code,
profiles or LUTs are reused. MEM-239's referenced [spektrafilm](https://github.com/andreavolpato/spektrafilm)
was consulted for its high-level pipeline and licensing; this ticket implements
only independent per-channel interpolation, not its spectral model.
