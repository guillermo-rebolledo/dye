# Contributing a Curve Set

Each Stock owns one directory named after its stable Profile `id`. The Baker reads
CSVs, never PDFs. Commit the source Curve Set and the resulting `.filmprofile`
together so reviewers can inspect changed numbers and CI can verify reproducibility.

The five `study-*` directories are **synthetic fixtures**, not manufacturer data or
accurate emulations. Their Display Names say so and all Provenance is artistic.
They exercise every Process and the entire authoring/loading/rendering path.
`portra-400` is the first measured Curve Set, using the spectral Baker path.
See [its sources](portra-400/SOURCES.md) and the [model contract](../docs/spectral-model.md)
for its measured inputs and explicitly artistic assumptions.

## Files

- `stock.json`: complete Profile metadata; copy a same-Process study as a template.
  See [the profile format](../docs/profile-format.md) for fields and units.
- Colour: one CSV per channel and sparse Development Offset. For a payload named
  `neutral.lut3d`, use `neutral.red.csv`, `neutral.green.csv`, `neutral.blue.csv`.
  For `push2.lut3d`, use `push2.red.csv`, etc. CSV names follow the **payload name**,
  never the Display Name. Each variant uses its own Curve Set; it is not a gain.
- B&W: for `density.curve1d`, use `density.csv`. `spectralWeight` lives in metadata.
  There are no colour-channel CSVs or Colour Cubes in this branch.
- For measured data, add `SOURCES.md` citing the manufacturer, datasheet edition,
  page/figure and digitisation method. Mark only supported parameters `measured`.
  Radii remain microns; Halation values are artistic, not datasheet measurements.

CSVs are UTF-8, one curve per file, with this exact header:

```csv
# Comments and blank lines are allowed.
logExposure,density
-1.505149978319906,0.05
-1.204119982655925,0.15
-0.9030899869919435,0.35
-0.6020599913279624,0.7
-0.3010299956639812,1.2
0,2
```

`logExposure` is base-10 log of **linear Working Space exposure**. Values must be
strictly increasing with no duplicates. At least two samples are required. Density
is nonnegative optical density, not a display code value. Both columns must be
finite numbers. Extra columns, quotes, missing values, NaN and infinity are errors.
The current trivial model supports positive exposure representable as float16 up
to 1 (`logExposure <= 0`); a production spectral model will define a wider shaper.

## Bake and validate

From the repository root on a Metal-capable Mac with Xcode:

```sh
swift build --product ProfileBaker
.build/debug/ProfileBaker bake Curves/study-c41 /tmp/study.filmprofile
.build/debug/ProfileBaker validate Curves/study-c41 /tmp/study.filmprofile /tmp/wedge 0.03
```

The output directory must already exist. Writes are atomic and failures exit
nonzero with a diagnostic. `validate` writes `wedge.csv` and `wedge.svg`, even when
the numerical comparison fails. Tolerance is an absolute density difference,
defaulting to 0.03 for these synthetic fixtures. Pick and justify a tolerance for
measured data; do not loosen it just to conceal a failed bake.

To ship a new Stock, add its directory to `Curves/`, then run:

```sh
Scripts/bake-catalogue.sh
swift test
```

This writes into `Sources/FilmEngine/Catalogue`. The package bundles that directory,
so new Profiles appear in the app picker on the next build with no source changes
and render with the exposure, white balance and development controls. Halation,
Grain and MTF are not yet applied. The CLI is a separate macOS executable product
and is not a dependency of FilmApp or the FilmEngine library.

## What the foundation study model does

For Curve Sets without `colour.inputShaper`, the Baker linearly interpolates density **in log-exposure space**, clamps beyond
the CSV endpoints, and evaluates that curve at the 33³ Colour Cube's linear grid
points. Each colour channel is independent: there is no spectral integration, DIR
coupling, Orange Mask, or scan/print transform. B&W uses the same interpolation to
bake a 1024-entry Density Curve. Runtime B&W collapses with the Profile's weights
and samples that curve. Film Response returns Density Space, which the runtime
Scan Output Stage inverts and auto-balances for display. Development Offsets blend
the two nearest baked variants; validation probes each baked variant exactly, with
the runtime scan disabled and the push rating cancelled by an equal exposure.

The numerical harness constructs a linear Step Wedge from every source sample and
log-space midpoint, renders it through the **public renderer entry point**, and
compares density to the source curve. It covers every channel and baked variant.
The CSV gives each input, reference, rendered density and error; the SVG overlays
the reference and rendered curves. No internal Metal pass is a test interface.
Quantisation and the finite Colour Cube grid limit accuracy; the harness measures
that error rather than asserting the Baker's own output against itself.

CI runs the process-level CLI tests, checks deterministic catalogue bytes and
validates every Curve Set, uploading the reports. Renderer tests require Metal;
a missing Metal device is a failure, not a silent test skip. For a custom SwiftPM
build directory set `PROFILE_BAKER_EXECUTABLE` to its absolute CLI path.

## Spectral Curve Sets

Portra adds `spectral.json`, `sensitivity.csv`, `dye-density.csv`, `observer.csv`,
`mtf.csv` and `rms-granularity.csv`. The three spectral tables must share a uniform
400…700 nm grid with 31–81 samples. Characteristic Curves use physical log10
lux-seconds within the metadata shaper range; `neutral.*.csv` supplies measured
normal development. Other offsets are calculated using the artistic contrast
and shadow-loss entries in `spectral.json`, not invented measured CSVs.

The Baker records a SHA-256 source fingerprint in the final Profile. It covers
the model version and all consumed authoring files, including metadata. Validation
rejects a Profile from a different source revision before comparing measurements.
Do not author a fingerprint in `stock.json`; it is derived during baking.

The spectral validation report distinguishes measured optical density (normal
development only) from numerical scan-output error (all variants). The default
0.03 bound applies in each stage's units. A passing scan comparison does not
validate the artistic colour model against a real photograph.
