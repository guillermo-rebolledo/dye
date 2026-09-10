# Performance audit

**Date:** 2026-09-10
**Commit audited:** `c19bc12` (branch `main`)
**Scope:** the `FilmEngine` render graph (both Render Paths), the Export Render Path
including Tile/Apron sizing and the Exported LUT, `ImageDecoder`, the Profile
Catalogue and Colour Cube residency, Metal resource and pipeline-state reuse,
`Sources/FilmEngine/Metal/Pipeline.metal`, the renderer actor's concurrency, and
SwiftUI invalidation and Metal surface lifetime in `FilmApp/`. Launch is covered.
`ProfileBaker/`, `Curves/` and `Scripts/` are out of scope: the Baker never ships.

## Method and limits

**This is a static source-reading audit.** It was performed on a Linux machine with
no Swift toolchain, no Xcode, no Metal, and no iOS device or simulator. **Nothing in
this document was measured by the author.** No build was run, no test was executed,
no Instruments trace was captured, no frame was rendered.

Every finding is grounded in a `file.swift:LINE` reference that was read in full.
Where a figure appears it is one of exactly three kinds, and each is labelled:

- **Derived** — arithmetic reproduced from the code's own constants and the
  Catalogue's own file headers (for example `TilePlan`'s tile count for a given
  frame, or a texture's byte size). Derived figures are exact given the source; they
  are not performance measurements and say nothing about wall-clock time.
- **Cited** — a number measured by someone else and recorded in this repository
  (`docs/export.md`, `docs/performance-audit.md`, `docs/audits/photo-open-responsiveness.md`).
  Attributed at the point of use, along with the hardware it was taken on.
- **Unverified** — an expectation about runtime behaviour that source reading cannot
  settle. Every one of these carries an explicit statement of the measurement that
  would confirm or kill it, and they are collected in the
  [Verification backlog](#verification-backlog).

Prior art was read before starting and is not repeated here:
`docs/performance-audit.md` (2026-09-09, fixes implemented),
`docs/audits/photo-open-responsiveness.md`, and the `DYE_PHOTO_OPEN_AUDIT=1` harness
in `Tests/FilmEngineTests/PhotoOpenAuditTests.swift`. Each of that audit's
implemented fixes was spot-checked against the current source; the results are in
[Confirmed healthy](#confirmed-healthy), including the two that were only partly
applied.

The headline result is that the **Export Render Path, not the Preview, is where this
app is in trouble**. Two findings there — PERF-01 and PERF-02 — are of a different
order from everything else, and both are arithmetic rather than speculation.

---

## Summary

| ID | Title | Severity | Confidence | Effort | Render Path |
| --- | --- | --- | --- | --- | --- |
| [PERF-01](#perf-01) | Tile plan degenerates above a ~4 500 px frame: 44× overdraw | Critical | Confirmed-from-source | L | Export |
| [PERF-02](#perf-02) | Full-resolution decode holds ~1.45 GB of buffers at once | Critical | Confirmed-from-source | M | Export |
| [PERF-03](#perf-03) | The whole Catalogue re-renders after every settings change, on screen or not | High | Confirmed-from-source | S | Preview |
| [PERF-04](#perf-04) | Four-entry Colour Cube cache thrashes on every Catalogue sweep | High | Confirmed-from-source | M | Both |
| [PERF-05](#perf-05) | The renderer actor blocks in `waitUntilCompleted` for the whole GPU pass | High | Likely | M | Both |
| [PERF-06](#perf-06) | Export and Preview share a Renderer and thrash ~300 MB of pyramid textures | High | Confirmed-from-source | M | Both |
| [PERF-07](#perf-07) | Bloom and Halation keep separate Scattering Pyramids they never use at once | Medium | Confirmed-from-source | M | Both |
| [PERF-08](#perf-08) | About fifty compute command encoders per Preview frame, one per dispatch | Medium | Likely | S | Both |
| [PERF-09](#perf-09) | Every intermediate is `.shared` storage with `.renderTarget` usage | Medium | Needs measurement | S | Both |
| [PERF-10](#perf-10) | The Metal library is compiled from `.metal` source at every `Renderer()` | Medium | Confirmed-from-source | M | Launch |
| [PERF-11](#perf-11) | The render `Plan` — including the MTF fit — is rebuilt for every Tile | Medium | Confirmed-from-source | S | Both |
| [PERF-12](#perf-12) | `ImageWriter` quantises scalar in `Double` on the renderer actor | Medium | Likely | S | Export |
| [PERF-13](#perf-13) | Blur kernels recompute `exp()` per tap per pixel; library-wide safe math | Medium | Needs measurement | S | Both |
| [PERF-14](#perf-14) | `.id(model.selectedStock)` tears down the Metal canvas on every Stock change | Medium | Confirmed-from-source | S | Preview |
| [PERF-15](#perf-15) | Every Preview frame round-trips 24 MB through the CPU to reach the canvas | Medium | Likely | L | Both |
| [PERF-16](#perf-16) | `exportedLUT` formats the file with `String(format:)` per component | Low | Confirmed-from-source | S | Export |
| [PERF-17](#perf-17) | Renderer construction is serialised ahead of the Photos transfer | Low | Confirmed-from-source | S | Preview |
| [PERF-18](#perf-18) | Contact Sheet builds a third Renderer and re-reads the Catalogue per open | Low | Confirmed-from-source | S | Preview |
| [PERF-19](#perf-19) | 210 MB Catalogue in the bundle; one Stock is 79 MB of it | Low | Confirmed-from-source | M | Launch |
| [PERF-20](#perf-20) | SwiftData container is created synchronously at launch | Low | Needs measurement | S | Launch |

---

<a id="perf-01"></a>
## PERF-01 — Tile plan degenerates above a ~4 500 px frame: 44× overdraw

**Severity** Critical · **Confidence** Confirmed-from-source · **Effort** L · **Path** Export

### What the code does today

The Apron is sized to the Bloom Pass's reach, and Bloom is 900 Film-Plane Microns —
the widest blur in the pipeline, as `Renderer.swift:284-289` says. That reach is
converted to pixels through Frame Width, so it grows **linearly with the frame's long
edge**, while the Tile texture budget (`ExportOptions.textureBudgetBytes`, default
`320 << 20`, `ExportTypes.swift:72`) is fixed.

`TilePlan.init` divides the fixed budget between Apron and core, and when the Apron
does not fit it caps the Apron and lets the core fall to the floor:

```swift
// TilePlan.swift:83
self.apron = min(apron, max(0, (budgetEdge - minimumCore) / 2))
// TilePlan.swift:90
let core = max(aligned(minimumCore, up: true), aligned(max(0, budgetEdge - 2 * apron), up: false))
```

Once the cap binds, `budgetEdge - 2 * apron` **is** `minimumCore` by construction, so
the core collapses to exactly `minimumCore` (256, `ExportTypes.swift:72`) and the
whole budget is spent on Apron.

Reproducing that arithmetic from the source constants —
`Renderer.scatterLevelSigmas` (`Renderer.swift:698-708`), `Scatter.reach`
(`Renderer.swift:342`), `Scatter.alignment` (`Renderer.swift:347`),
`apronFraction: 0.6` (`ExportTypes.swift:74`) and `TilePlan.tileTextureCount = 14`
(`TilePlan.swift:112`) — gives (all **derived**, not measured):

| Frame | Bloom σ (px) | Top level | Requested Apron | Apron used | Core | Padded Tile | Tiles | Pixels rendered / frame pixels |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 4032 × 3024 (iPhone 12 MP) | 100.8 | 6 | 476 | 476 | 704 | 1664 × 1680 | 30 | **6.9×** |
| 4480 × 3360 (~15 MP) | 112.0 | 6 | 476 | 476 | 704 | 1664 × 1696 | 35 | **6.6×** |
| 4500 × 3375 | 112.5 | 7 | 956 | 673 (capped) | 256 | 1684 × 1711 | 252 | **47.8×** |
| 6000 × 4000 (24 MP) | 150.0 | 7 | 956 | 673 (capped) | 256 | 1648 × 1696 | 384 | **44.7×** |
| 8064 × 6048 (iPhone 48 MP) | 201.6 | 7 | 956 | 673 (capped) | 256 | 1664 × 1696 | 768 | **44.4×** |

The 32 × 24 grid and the "673, capped from 956" figure in the 48 MP row of
`docs/export.md:159-163` match this derivation exactly, which is a useful independent
check that the arithmetic above reads the code correctly.

Two things are worth naming precisely.

1. **There is a cliff, not a slope.** The Scattering Pyramid's level sigmas are
   geometric (`Renderer.swift:698-708`), so `topLevel` steps from 6 to 7 the moment
   Bloom's sigma passes 112.4 px — a frame long edge of about **4 495 px** for a
   36 mm Frame Width. Below it: 30 Tiles and 6.9× overdraw. Above it: 384 Tiles and
   44.7×. An iPhone HEIF at 4032 px sits just under the cliff; **any 24 MP import,
   and iPhone 48 MP ProRAW, sits just over it.**
2. **At the cap both goals fail at once.** `docs/export.md:69` states that below about
   half of the full reach "the truncation starts to be a seam". The capped Apron of
   673 against a requested 956 is 0.42 of the reach — already under that floor — and
   it is bought with a 256-px core, which is the least efficient Tile the plan can
   produce. The plan spends 44× the work to deliver an Apron it has itself judged too
   short.

`ExportOptions` is never overridden by the app: `EditorModel.swift:328` passes
`ExportOptions(creationDate: creationDate)`, so every user Export uses these defaults.

### Why it costs

Each of the 768 Tiles runs the entire thirteen-Pass graph over 1664 × 1696 pixels to
keep a 256 × 256 core — 2.4 % of what it rendered. The graph is roughly fifty
dispatches per Tile (see [PERF-08](#perf-08)), so a 48 MP Export encodes on the order
of 38 000 compute dispatches over 2.17 billion pixel-passes (**derived**).

### User-visible symptom

A 48 MP or 24 MP Export takes minutes, heats the device, and — because Grain degrades
to the procedural model under throttling (`Export.swift:118-124`) and the loop sleeps
50 ms per Tile when throttling (`Export.swift:92`) — gets slower the longer it runs.
`docs/export.md:162` records **13.0 s for a 48 MP Export on an Apple Silicon Mac**
(cited, not measured here); a phone GPU under a thermal cap will be a substantial
multiple of that. This is unverified on device and is the single most important
measurement in the [Verification backlog](#verification-backlog).

### Proposed change

Three options, in increasing order of value and effort. They are not exclusive.

1. **(S) Stop the core collapsing.** Bound the Apron by a *share* of the budget edge
   rather than by "everything except `minimumCore`" — for example
   `apron = min(requested, max(0, (budgetEdge - minimumCore) / 2), budgetEdge / 3)`,
   which leaves a core of about `budgetEdge / 3`. **Derived**: at 48 MP that gives an
   Apron of 534 and a core of 534, so 16 × 12 = 192 Tiles and about 10× overdraw —
   4.4× less work, the same memory. It also makes the Apron *shorter* (0.34 of reach
   against 0.42), so it trades seam margin for time and must be measured against
   `aTiledExportReproducesTheUntiledRenderOfTheSameFrame`
   (`Tests/FilmEngineTests/ExportTests.swift:123`) before it is taken.
2. **(M) Scale the budget to the device.** `textureBudgetBytes` is a fixed 320 MB on
   every device. Read `os_proc_available_memory()` at Export start and scale.
   **Derived**: at a 640 MB budget with the shared-pyramid saving from
   [PERF-07](#perf-07) (`tileTextureCount` 14 → 8), a 48 MP frame plans 42 Tiles of
   3072 × 3104 with a full uncapped 956 Apron and 8.2× overdraw — both faster *and*
   exact. Peak Tile-texture memory would be about 610 MB, which is only viable on
   large-memory devices and only alongside [PERF-02](#perf-02).
3. **(L) Compute the coarse Scattering Pyramid levels once per frame.** This is the
   architecturally correct fix and it makes the Export both faster and *more* exact.
   The Apron exists only so each Tile's coarse pyramid levels agree with the untiled
   render's. Levels 4 and above are a 16×-or-more downsample of the frame — 504 × 378
   at 48 MP, trivially cheap — and carry no high-frequency content. Build levels 4…N
   once from a whole-frame downsample, in frame coordinates, and have each Tile build
   only levels 0…3 locally and sample the shared coarse levels by frame position. The
   Apron then only has to cover levels 0…3, which is `12.5 · 2³ − 7.5 = 92.5` px
   (`Renderer.swift:342`). **Derived**: at 48 MP that is an Apron of 93, a core of
   1416, 6 × 5 = 30 Tiles and **1.6× overdraw** — a 28× reduction against today,
   within the existing 320 MB budget, with a *wider* effective reach than the capped
   Apron delivers now.

### Acceptance criteria

- For an 8064 × 6048 frame with Cinestill 800T at default `ExportOptions`,
  `TilePlan.count ≤ 64` and total rendered pixels ≤ 4× frame pixels.
- `TilePlan.isApronCapped` is `false` for every frame up to 8064 × 6048 at default
  options, or the capped Apron is at least 0.5 of `requestedApron`.
- `aTiledExportReproducesTheUntiledRenderOfTheSameFrame` still passes at both
  `apronFraction: 1` (max difference exactly 0) and the default (< 1/255).
- `halationHasNoTileSeamWhereAPointLightStraddlesABoundary` and
  `grainIsSampledInImageGlobalCoordinatesAndDoesNotRepeatAtTheTilePitch` still pass.
- Peak Tile-texture bytes stay within `options.textureBudgetBytes`.

### How to verify

On a Mac with Xcode:

```sh
swift test -c release --filter 'tilePlanCoversTheFrameExactly|apronFollowsTheWidestBlur|aTiledExportReproducesTheUntiledRender|halationHasNoTileSeam|grainIsSampledInImageGlobal'
```

Add a diagnostic that prints `count`, `coreWidth`, `paddedWidth`, `apron`,
`requestedApron` and `isApronCapped` for 4032 × 3024, 4500 × 3375, 6000 × 4000 and
8064 × 6048, so the cliff is a checked-in table rather than a derivation.

On device, run the Export from Instruments' **Metal System Trace** with the **Thermal
State** track on, for a 48 MP ProRAW frame through Cinestill 800T, and record
wall-clock, GPU utilisation, and whether the thermal state reaches `.serious`.

---

<a id="perf-02"></a>
## PERF-02 — Full-resolution decode holds ~1.45 GB of buffers at once

**Severity** Critical · **Confidence** Confirmed-from-source · **Effort** M · **Path** Export

### What the code does today

`Renderer.export` starts by decoding the whole frame:

```swift
// Export.swift:16
let source = try texture(for: image)
```

which for `.encoded` reaches `ImageDecoder.decode(data, maximumDimension: nil)`
(`Renderer.swift:118`). The non-RAW branch allocates a Float32 staging buffer, draws
the colour-managed image into it, divides out premultiplication scalar, maps to
Float16, and uploads:

```swift
// ImageDecoder.swift:81-82
let texture = try makeTexture(width: width, height: height)
var pixels = [Float](repeating: 0, count: width * height * 4)
...
// ImageDecoder.swift:105-108
for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 0 {
    for c in 0..<3 { pixels[i + c] /= pixels[i + 3] }
}
let half = pixels.map(Float16.init)
```

`pixels`, `half` and `texture` are all live simultaneously at line 109, because
`pixels` stays in scope to the end of the function.

**Derived**, for an 8064 × 6048 frame:

| Allocation | Line | Bytes |
| --- | --- | --- |
| RGBA16F source texture | `ImageDecoder.swift:81` | 372 MB |
| `[Float]` staging buffer | `ImageDecoder.swift:82` | 744 MB |
| `[Float16]` mapped copy | `ImageDecoder.swift:108` | 372 MB |
| **Live at once** | | **1.45 GB** |

That is before the Export has rendered a single Tile. The Tile textures then add
about 304 MB (**cited**, `docs/export.md:163`) and `ImageWriter.pixels` adds 186 MB
for HEIF or 372 MB for 16-bit TIFF (`ImageWriter.swift:35`, **derived**), on top of
the encoded original that `EditorModel` retains (`EditorModel.swift:35`,
`EditorModel.swift:172`) and the Preview textures the same Renderer is still holding
(see [PERF-06](#perf-06)).

Two secondary costs live in the same function. The premultiply-divide loop
(`ImageDecoder.swift:105-107`) is 146 million scalar divisions for a 48 MP frame
(**derived**), and `pixels.map(Float16.init)` is a second full-size allocation plus
195 million conversions.

### Why it costs

`ImageWriter`'s own doc comment (`ImageWriter.swift:14-16`) reasons carefully about
183 MB for the assembled frame against 380 MB per intermediate — but the decode that
precedes it is four times either figure, and nothing in the code or the docs accounts
for it. `TilePlan`'s doc comment (`TilePlan.swift:5-10`) exists precisely because a
48 MP frame does not fit in memory whole; the source texture is exactly such an
allocation, held for the entire Export.

### User-visible symptom

Most likely a jetsam kill — the app disappears — when exporting a large photograph,
particularly on 4 GB devices. `README.md` already says "a simulator does not
reproduce the memory pressure tiling exists for", and this is the specific pressure.
**Unverified**: whether it actually terminates depends on the device's memory limit
and on what else is resident. The measurement that settles it is in the backlog.

### Proposed change

1. **Decode in horizontal bands.** Loop over bands of rows: create the `CGContext`
   for one band with the appropriate `translateBy`, draw, unpremultiply, convert, and
   `texture.replace` that band's region. Peak extra becomes one band rather than
   1.08 GB. Orientation handling (`ImageDecoder.swift:91-99`) has to be applied to the
   whole-image transform with the band offset composed in, and needs a test per
   orientation case.
2. **Drop the Float32 hop if the platform allows it.** Check whether a `CGContext`
   with `bitsPerComponent: 16` and `CGBitmapInfo.floatComponents` over
   `extendedLinearITUR_2020` is a supported pixel format on the deployment target.
   If it is, `pixels` and `half` collapse into one buffer at half the size and
   `pixels.map(Float16.init)` disappears. **Unverified** — this is a platform
   capability question that requires an iOS device or simulator to answer.
3. **Vectorise the unpremultiply.** `vImageUnpremultiplyData_RGBAFFFF` replaces the
   146-million-iteration scalar loop, or the divide can move into the shader by
   uploading premultiplied pixels and dividing in `passthrough`.
4. **Release the source texture before `writer.encode`.** `Export.swift:22` encodes
   while `source` is still in scope; the last Tile no longer needs it.

### Acceptance criteria

- Peak resident bytes attributable to `ImageDecoder.decode` for an 8064 × 6048 input
  are under 1.5× the size of the destination texture (≤ 560 MB), down from ~3.9×.
- `taggedPhotosUseTheirOwnPrimaries`, `untaggedInputDoesNotSilentlyAssumeSRGB`,
  `identityColourCubePreservesEveryFiniteHalfValue` and
  `rawDecodePreservesSceneLinearExposureRatios` all still pass.
- A band-decoded image is bit-identical to a whole-image decode, for every one of the
  eight EXIF orientations and for an image with alpha.

### How to verify

```sh
swift test -c release --filter 'taggedPhotos|untaggedInput|identityColourCube|rawDecode|previewDownsampl'
```

Add a decode test that walks all eight orientations and asserts bit equality against
today's whole-image path (capture the current output as a fixture first).

On device: Instruments **Allocations** with the **VM Tracker** and **Memory Terminations**
instruments, exporting a 48 MP ProRAW frame as 16-bit TIFF (the worst case) on the
smallest-memory supported device. Record `Persistent Bytes` peak and any jetsam event.
`os_proc_available_memory()` logged at Export start and at the end of decode gives a
cheap in-app cross-check.

---

<a id="perf-03"></a>
## PERF-03 — The whole Catalogue re-renders after every settings change, on screen or not

**Severity** High · **Confidence** Confirmed-from-source · **Effort** S · **Path** Preview

### What the code does today

`scheduleRender()` unconditionally schedules a Catalogue-wide thumbnail sweep before
it schedules the Preview:

```swift
// EditorModel.swift:550-552
func scheduleRender() {
    scheduleThumbnails()
    needsRender = true
```

and `scheduleRender()` is the `didSet` of `settings` (`EditorModel.swift:15`), so
every movement of every dial, every Adjustment, every Development Offset step queues
a full-Catalogue render. `scheduleThumbnails()` (`EditorModel.swift:474-483`) renders
`catalogueWithIdentity` — 18 Profiles — through
`scheduleThumbnails(_:plan:store:)` (`EditorModel.swift:518-548`) after a 200 ms
debounce.

The filmstrip those thumbnails feed is presented in a sheet
(`EditorPickers.swift:26-39`), so **it is not on screen for the overwhelming majority
of the time these renders run**. Nothing checks whether it is.

The debounce coalesces a continuous drag, but every *settle* — every time a finger
lifts, every tap on a discrete control, every Preset applied, every Stock change
(`stockChanged()`, `EditorModel.swift:188-195`) — starts one sweep of 18 renders.

### Why it costs

The thumbnail input is 192 px (`EditorModel.swift:178`), so the pixel work is
negligible. The cost is entirely in the Colour Cubes each Profile pulls in, and with
the cache at four entries none of it is reused between sweeps — see
[PERF-04](#perf-04). **Derived**, a full sweep at default settings touches about
**53.6 MB** of Colour Cube payload: eight 65³ colour Stocks at two cubes each
(2.10 MB per cube), Cinestill's 129³ film cube at 16.38 MB plus its 65³ output cube,
three 33³ studies, and four monochrome Density Curves at 2 KB.

Each of those is a `FileHandle` open/seek/read (`Profile.swift:47-53`), a
`[Float16]` allocation with a finite-bit check (`ProfileContainer.swift:135-169`), a
3D `MTLTexture` allocation and a full upload (`Renderer.swift:1001-1014`) — and then
an eviction.

### User-visible symptom

A pause 200 ms after every control settles, on the same Renderer actor the
Output Stage cards use; and continuous file I/O, allocation churn and GPU upload
traffic while the user is grading, which is exactly the wrong time for it. Battery
and thermal cost is proportional. **Unverified**: how long a sweep takes on device.

### Proposed change

- Gate the sweep on the filmstrip being visible. `EditorSelection.isFilmstripOpen`
  already exists (`EditorPickers.swift:26`); pass it down or have `EditorModel` hold
  it, and have `scheduleThumbnails()` return early when the strip is closed, marking
  the thumbnails stale so they refresh when it opens.
- Separate the two schedulers. `scheduleRender()` should schedule the Preview; the
  filmstrip should schedule itself from a `.task(id:)` on the sheet keyed by
  `(thumbnailGeneration, settings, selectedStock)`, which is the same pattern
  `OutputStageCards` already uses correctly (`OutputStageCards.swift:45`, `:66-72`).
- While the sweep is running, render the *selected* Stock first so the cell the user
  is looking at updates before the seventeen they are not.

### Acceptance criteria

- With the filmstrip sheet closed, moving any dial and letting it settle performs
  exactly one render (the Preview) and zero Catalogue renders.
- Opening the filmstrip after a settings change refreshes all cells; no cell shows a
  thumbnail rendered at stale settings without being marked developing first.
- `stockChanged()` results in exactly one Preview render, not two (see
  [PERF-04](#perf-04) acceptance criteria).

### How to verify

Add a counter to `EditorModel` (debug-only) incremented per `renderer.render` call and
assert it in a UI test that drags a dial with the strip closed. On device, Instruments
**Time Profiler** plus **File Activity**: with the strip closed, dragging Exposure and
releasing should produce no `read(2)` traffic against `*.filmprofile`.

---

<a id="perf-04"></a>
## PERF-04 — Four-entry Colour Cube cache thrashes on every Catalogue sweep

**Severity** High · **Confidence** Confirmed-from-source · **Effort** M · **Path** Both

### What the code does today

`Renderer.responseCache` is an LRU of fixed **entry count**, defaulting to four:

```swift
// Renderer.swift:32-34
public init(textureCacheCapacity: Int = 4) throws {
    guard (2...32).contains(textureCacheCapacity) else { ... }
// Renderer.swift:987-988
responseCache.append(entry)
if responseCache.count > textureCacheCapacity { responseCache.removeFirst() }
```

No call site in `FilmApp/` passes a capacity, so every Renderer in the app uses four
(`EditorModel.swift:152`, `:510`; `ContactSheetView.swift:66`).

A single `plan()` can ask for four entries at once: lower and upper Film Response
cubes for a fractional Development Offset, plus lower and upper density-output cubes
for the Output Stage (`Renderer.swift:464-482`). So a mid-push Portra 400 Print fills
the cache on its own, and **the next Profile evicts all of it**.

Counting by entries rather than by bytes also means the cache cannot know that
Cinestill's `lutSize` is 129 while every other Stock's is 65. **Derived** from the
container headers: a 65³ cube is 2.10 MB, a 129³ cube is 16.38 MB. Four entries is
therefore anywhere between 8 KB (four monochrome Density Curves) and 65 MB (four
Cinestill film cubes).

Cold-loading one entry is, per `Renderer.swift:945-990`: a `FileHandle` open and read
(`Profile.swift:47-53`), a `[Float16]` allocation and finite-bit sweep
(`ProfileContainer.swift:135-169`), two `ColourCube.sample` calls, a 3D texture
allocation and a full `replace` upload (`Renderer.swift:1001-1014`) — all on the
renderer actor, all inside `plan()`, all in the middle of a frame.

### Why it costs

Every Catalogue-wide surface pays the full 53.6 MB (**derived**) each time it runs,
and there are three of them: the filmstrip sweep after every settings change
([PERF-03](#perf-03)), the Contact Sheet on every open ([PERF-18](#perf-18)), and
the Preset sheet's rows (`EditorModel.swift:222-235`).

Even in the single-Stock Preview case the cache is tight. Dragging the Development
Offset dial across a whole stop changes the `(lower, upper)` variant pair, which for
Cinestill means a cold 16.38 MB read-decode-upload **inside the render**, and
switching between Scan and Print alternates four different textures against a
four-entry cache.

### User-visible symptom

A hitch on Stock change and on crossing a Development Offset stop, worst on Cinestill
800T; sustained file and allocation traffic during grading; and repeated cost every
time the Contact Sheet or the filmstrip opens.

### Proposed change

- **Budget the cache in bytes, not entries.** Replace `textureCacheCapacity: Int` with
  a byte budget, track each entry's texture size, and evict LRU until under budget.
  A 96 MB budget holds the entire Catalogue's default-settings working set
  (53.6 MB, derived) with headroom for a Development Offset blend.
- **Do not let one plan evict its own inputs.** Whatever the policy, entries acquired
  for the plan currently being built must be pinned until it is encoded. Today a
  capacity of 2 or 3 (both legal, `Renderer.swift:33`) would silently do so.
- **Load cold cubes off the render.** `responseEntry` performing file I/O inside
  `plan()` inside `render()` means a Stock change stalls the actor. Prefetching the
  selected Stock's cubes when the picker's selection changes, before the render is
  requested, would move the stall out of the frame.
- **Respond to memory pressure.** Register a `DispatchSource.makeMemoryPressureSource`
  and drop the cache (and the retained pyramids) on `.warning`.

### Acceptance criteria

- Rendering the whole Catalogue twice in a row through one Renderer reads each
  `.filmprofile` payload at most once (assert with a payload-read counter on
  `Profile`).
- A capacity/budget too small to hold one `plan()`'s entries is rejected at init, or
  the plan's own entries are pinned; a regression test renders a fractional
  Development Offset Print through a minimum-budget Renderer and gets the same pixels
  as a large-budget one.
- Peak texture bytes held by `responseCache` never exceed the configured budget.
- `stockChanged()` (`EditorModel.swift:188-195`) schedules one render, not two: it
  assigns `settings` (which fires `didSet` → `scheduleRender()`,
  `EditorModel.swift:15`) and then calls `scheduleRender()` again at line 194.

### How to verify

```sh
swift test -c release --filter 'repeatedPreviewRendersMatchFreshRenderers|catalogue|golden'
```

Add a test that renders `ProfileCatalogue.bundled().profiles` twice through one
Renderer and asserts the second pass issues no payload reads. On device, Instruments
**File Activity** while opening the filmstrip twice: the second open should read no
profile bytes.

---

<a id="perf-05"></a>
## PERF-05 — The renderer actor blocks in `waitUntilCompleted` for the whole GPU pass

**Severity** High · **Confidence** Likely · **Effort** M · **Path** Both

### What the code does today

Every submission blocks the actor's thread until the GPU is finished:

```swift
// Renderer.swift:247-249
command.commit()
command.waitUntilCompleted()
if let error = command.error { throw error }
```

The same pattern appears in the per-Tile blit (`Export.swift:110-112`) and the RAW
decode (`ImageDecoder.swift:55-56`).

`Renderer` is an `actor` (`Renderer.swift:6`), so a blocking call inside it occupies
the actor for the entire GPU pass. Nothing else can enter — not another Preview
frame, not a thumbnail, not the Output Stage cards.

`Export.swift:88-92` documents the intent that the Preview can be serviced between
Tiles:

```swift
if thermalState.isThrottling { try await Task.sleep(for: .milliseconds(50)) } else { await Task.yield() }
```

That is correct as far as it goes — the `await` is a genuine suspension point and the
actor is reentrant there — but *during* a Tile the actor is held, so a Preview frame
requested mid-Tile waits out that Tile's GPU time plus its readback plus
`ImageWriter.write` ([PERF-12](#perf-12)).

### Why it costs

Two things. First, no CPU/GPU overlap: the CPU sits idle waiting rather than encoding
the next command buffer. Second, the actor is the app's only serialisation point for
the renderer, so blocking it converts every concurrent request into a queue.

### User-visible symptom

The Preview freezes for the duration of a Tile while an Export runs — which, given
[PERF-01](#perf-01), is 768 Tiles for a 48 MP frame. Combined with
[PERF-06](#perf-06), editing during an Export is likely to be unusable.
**Unverified**: the per-Tile stall duration on device.

### Proposed change

Replace `waitUntilCompleted()` with a suspension:

```swift
try await withCheckedThrowingContinuation { continuation in
    command.addCompletedHandler { buffer in
        if let error = buffer.error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }
    command.commit()
}
```

This is **not a mechanical change**, and the reason is the point of the finding:
`previewTextures`, `pyramids` and `mtfTextures` (`Renderer.swift:18-20`) are actor
state that the in-flight command buffer is reading and writing. Suspending mid-render
makes the actor reentrant at exactly the moment those textures are live, so a second
render entering could reallocate or overwrite them — which is the class of bug
`repeatedPreviewRendersMatchFreshRenderers`
(`Tests/FilmEngineTests/RendererTests.swift:87`) was written to catch.

The change therefore needs an explicit in-flight guard: either a serialisation token
that a second render awaits before touching shared textures, or per-render ownership
of the scratch set (which costs memory — see [PERF-07](#perf-07)). Do the guard
first, then the suspension.

### Acceptance criteria

- `Renderer.render` and `Renderer.renderTile` contain no `waitUntilCompleted`.
- Two concurrent `render` calls with different dimensions and different Profiles
  produce the same pixels as two sequential calls (extend
  `repeatedPreviewRendersMatchFreshRenderers`).
- With an Export running, a Preview render started mid-Tile completes without waiting
  for that Tile.

### How to verify

```sh
swift test -c release --filter 'repeatedPreviewRendersMatchFreshRenderers|aTiledExportReproducesTheUntiledRender|exportProgressIsReportedPerTile'
```

Add a test that launches an Export and issues Preview renders concurrently, asserting
both complete and both are bit-identical to their serial equivalents. On device,
Instruments **Metal System Trace**: the CPU encode track should overlap the GPU track
rather than alternating with it.

---

<a id="perf-06"></a>
## PERF-06 — Export and Preview share a Renderer and thrash ~300 MB of pyramid textures

**Severity** High · **Confidence** Confirmed-from-source · **Effort** M · **Path** Both

### What the code does today

`EditorModel.exportImage` exports through the **same** Renderer the Preview uses:

```swift
// EditorModel.swift:300
guard let original, let renderer, exportTask == nil else { return }
// EditorModel.swift:327
let data = try await renderer.export(image: .encoded(original), profile: profile, ...)
```

The Scattering Pyramids and MTF textures are cached on that Renderer and keyed by
dimensions, reallocating whenever the dimensions change:

```swift
// Renderer.swift:780-782
if let pyramid = pyramids[scattering], pyramid.count == count,
   pyramid.levels[0].width == width, pyramid.levels[0].height == height { return pyramid }
// Renderer.swift:852-853
if let textures = mtfTextures, textures[0].width == width, textures[0].height == height { return textures }
```

A Preview is 2048 px on its long edge (`EditorModel.swift:29`); an Export Tile is
about 1664 × 1696 (**derived**, see [PERF-01](#perf-01)). They never match. So every
time the Export yields between Tiles (`Export.swift:92`) and the Preview render loop
(`EditorModel.swift:554-571`) gets in, the pyramids and MTF textures are reallocated
to Preview size — and the next Tile reallocates them back.

**Derived** allocation for a 2048 × 1536 Preview of a Stock with both Scattering
Passes active (Bloom resolves to a six-level pyramid, Halation to four at Portra
400's 220 µm):

| Resource | Line | MB |
| --- | --- | --- |
| `previewTextures` (input + scratch) | `Renderer.swift:19`, `:87-88` | 48.0 |
| `mtfTextures` (three) | `Renderer.swift:20`, `:854` | 72.0 |
| Bloom pyramid, 6 levels (raw + levels + scratch) | `Renderer.swift:780-797` | 88.0 |
| Halation pyramid, 4 levels | `Renderer.swift:780-797` | 87.8 |
| **Retained per Renderer** | | **295.7** |

Against 304 MB of Tile textures during Export (**cited**, `docs/export.md:163`), each
interleave is on the order of a quarter-gigabyte of texture allocation and release.

### Why it costs

Large `MTLTexture` allocation is not free — it is a page-backed VM mapping, and doing
it in both directions between Tiles adds allocator and kernel time to a path that is
already the app's slowest. It also transiently doubles peak memory at the moment both
sets are live, on top of [PERF-02](#perf-02).

### User-visible symptom

Editing during an Export is slow in both directions: the Preview stalls and the
Export gets slower. **Unverified**: the reallocation cost per interleave.

### Proposed change

- **Give the Export its own Renderer.** It already has its own command queue
  (`Renderer.swift:11`, `:41-42`); the reason for that comment applies equally to the
  scratch textures. A dedicated export Renderer costs one more Metal library (see
  [PERF-10](#perf-10)) and one more Colour Cube cache, and removes the thrash
  entirely. This is also what makes [PERF-05](#perf-05)'s in-flight guard simpler.
- Or **key the caches by size rather than replacing them**: hold at most two sets, one
  per distinct dimension, evicting on memory pressure. Cheaper to write, but it
  doubles retained memory during Export.
- Either way, release the Preview-sized pyramids when the editor has been idle, or on
  `.warning` memory pressure. 296 MB retained by a Renderer that is not rendering is
  a lot to hold for a re-render that may not come.

### Acceptance criteria

- Running an Export while dragging a Preview dial performs zero pyramid or MTF
  reallocations attributable to dimension changes (assert with a debug counter on
  `pyramid(_:width:height:count:)` and `mtfTextures(width:height:)`).
- Preview render time during an Export is within 2× of Preview render time with no
  Export running.
- A memory-pressure warning releases the retained pyramids and Colour Cube cache.

### How to verify

Add a debug allocation counter and a test that alternates `render` at 2048 px with
`renderTile` at 1664 px, asserting the counter stays flat once warm. On device,
Instruments **Allocations** with `VM: IOAccelerator` filtering, exporting while
dragging Exposure.

---

<a id="perf-07"></a>
## PERF-07 — Bloom and Halation keep separate Scattering Pyramids they never use at once

**Severity** Medium · **Confidence** Confirmed-from-source · **Effort** M · **Path** Both

### What the code does today

```swift
// Renderer.swift:16-18
/// One per Scattering Pass: Bloom and Halation ask for different radii, so they
/// resolve to pyramids of different depths and cannot share one allocation.
private var pyramids: [Scattering: Pyramid] = [:]
```

The two Passes are strictly sequential. `Pass.allCases` orders `bloom` before
`halation` (`Renderer.swift:1021`), and the loop in `execute` runs one, swaps the
ping-pong textures, then runs the other (`Renderer.swift:164-172`). Bloom's
`scatterComposite` (`Renderer.swift:844-846`) is the last read of Bloom's pyramid;
Halation's `scatterThreshold` is the first write of Halation's.

The stated reason for not sharing is that they resolve to different depths. That is a
sizing question, not a lifetime one: allocating to the deeper of the two and using a
prefix satisfies both. `MTF` adds three more full-size textures
(`Renderer.swift:852-857`) that are likewise dead before the Film Response and could
draw from the same pool.

`TilePlan.tileTextureCount = 14` (`TilePlan.swift:112`) is derived from exactly this
layout — "the two ping-pong textures, three for the MTF Pass, and a Scattering Pyramid
each for Bloom and Halation" — and it is the divisor of the Export memory budget
(`TilePlan.swift:73-76`).

### Why it costs

**Derived**, for a 2048 × 1536 Preview: sharing one pyramid saves 87.8 MB of the
295.7 MB in [PERF-06](#perf-06)'s table; pooling the MTF textures into the same
allocation saves a further 72 MB. That is more than half of the Renderer's retained
texture memory, and there are two Renderers live in the editor
(`EditorModel.swift:31`, `:24`).

For Export it reduces `tileTextureCount` from 14 to about 8, which raises `budgetEdge`
from 1602 to about 2192 within the same 320 MB budget.

**Important caveat, derived:** on its own this does *not* speed up a 48 MP Export.
Because the core collapses to `minimumCore` whenever the Apron is capped
([PERF-01](#perf-01)), a larger `budgetEdge` produces a larger *padded* Tile at the
same 256-px core — 768 Tiles of 2176 × 2208 instead of 768 of 1664 × 1696, which is
*worse*. This finding is worth taking for the memory, and it becomes worth taking for
speed only in combination with PERF-01's option 1 or 3.

### Proposed change

- Replace `pyramids: [Scattering: Pyramid]` with one pyramid sized to
  `max(bloomLevels, halationLevels)` for the current dimensions, and have
  `encodeScatter` use `levels.prefix(count)`.
- Pool the three MTF textures from the same allocation (they are full-size, as
  `levels[0]`, `scratch[0]` and `raw` are).
- Update `TilePlan.tileTextureCount` and its doc comment to match whatever the new
  layout actually holds, and add a test that asserts the constant against the
  Renderer's real allocation count so the two cannot drift.

### Acceptance criteria

- `Renderer` allocates at most one Scattering Pyramid per dimension pair.
- Retained texture bytes for a 2048 × 1536 Preview of Portra 400 at default settings
  fall by at least 80 MB.
- `TilePlan.tileTextureCount` equals the number of Tile-sized RGBA16F textures the
  graph actually holds, asserted by a test rather than by comment.
- `aTiledExportReproducesTheUntiledRenderOfTheSameFrame` and every Bloom/Halation
  golden image are unchanged.

### How to verify

```sh
swift test -c release --filter 'Bloom|Halation|Scatter|aTiledExportReproduces|golden'
```

---

<a id="perf-08"></a>
## PERF-08 — About fifty compute command encoders per Preview frame, one per dispatch

**Severity** Medium · **Confidence** Likely · **Effort** S · **Path** Both

### What the code does today

Every dispatch opens and closes its own `MTLComputeCommandEncoder`:

```swift
// Renderer.swift:910-919
guard let encoder = command.makeComputeCommandEncoder(), let pipeline = pipelines[name] else { ... }
...
encoder.endEncoding()
```

The same shape appears in the main pass loop (`Renderer.swift:207-244`) and in
`encodeScatter`'s local `dispatch` (`Renderer.swift:809-821`).

**Derived**, for a 2048 × 1536 Preview of Portra 400 at default settings — Bloom
resolves to a six-level pyramid and Halation to four
(`Renderer.swift:755-757`, `:780-797`):

| Group | Encoders |
| --- | --- |
| Bloom: threshold + 6×(blurH, blurV) + 5 downsample + scale + 5 upsample + composite | 25 |
| Halation: same shape at four levels | 17 |
| MTF: 4 blurs + combine (`Renderer.swift:859-878`) | 5 |
| Film Response, Grain, Output Stage, Output Transform, White Balance | up to 5 |
| **Total** | **~52** |

For the Export, multiply by 768 Tiles: about 38 000 encoders per 48 MP Export.

### Why it costs

A serial `MTLComputeCommandEncoder` already inserts the memory barriers the pass
graph needs between successive `dispatchThreads` calls on the same encoder, with
automatic hazard tracking for non-heap resources. Ending an encoder and starting
another is therefore paying for a hard boundary the code could get for free — and each
boundary costs driver-side encoding work and, on Apple GPUs, forfeits any chance of
back-to-back kernel launch.

**Unverified**: how much this is actually worth. It could be a few percent or it
could be double-digit; only a Metal System Trace on device will say. The claim about
serial-encoder hazard tracking should also be confirmed against current Metal
documentation before the change is written.

### Proposed change

Open one compute encoder per command buffer and issue every dispatch on it, ending it
once before `commit()`. Keep `encoder.label` semantics by using
`pushDebugGroup`/`popDebugGroup` per Pass so Metal frame capture is no less readable
than it is today.

### Acceptance criteria

- One `makeComputeCommandEncoder` call per command buffer in `execute`.
- Every golden image, the tiled/untiled equality test and the identity bit-exactness
  test are unchanged — this must be a pure encoding change.
- A Metal frame capture still shows one labelled debug group per Pass.

### How to verify

```sh
swift test -c release --filter 'golden|identityColourCubePreservesEveryFiniteHalfValue|aTiledExportReproducesTheUntiledRender'
```

On device: Instruments **Metal System Trace**, comparing "Command Buffer encode" CPU
time and total GPU time for one Preview frame before and after.

---

<a id="perf-09"></a>
## PERF-09 — Every intermediate is `.shared` storage with `.renderTarget` usage

**Severity** Medium · **Confidence** Needs measurement · **Effort** S · **Path** Both

### What the code does today

One factory makes every texture in the pipeline:

```swift
// ImageDecoder.swift:120-123
let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
descriptor.storageMode = .shared
```

That factory is used for the ping-pong pair (`Renderer.swift:87-88`, `:96`), every
Scattering Pyramid level and scratch (`Renderer.swift:791-794`), the three MTF
textures (`Renderer.swift:854`) and the Export Tile pair (`Export.swift:70-71`).

Of those, the CPU touches exactly two things: the input, via `replace`
(`Renderer.swift:105-108`), and whichever ping-pong texture holds the result, via
`getBytes` in `readback` (`Renderer.swift:935-943`) or `Export.swift:83-84`. The
pyramid levels, the pyramid scratch and the MTF textures — 11 of the 14 the Export
budget counts — are never read or written by the CPU at all.

`.renderTarget` is requested but nothing in `Pipeline.metal` is a render pass; every
kernel is a compute kernel writing through `texture2d<half, access::write>`.

### Why it costs

`.shared` storage makes a texture CPU-coherent, which on Apple GPUs forgoes lossless
framebuffer compression. A thirteen-Pass graph is bandwidth-bound almost by
definition — about fifty full-surface reads and writes per frame ([PERF-08](#perf-08))
— so compression on the intermediates is the kind of thing that can matter.

**This is the least certain finding in the document.** Whether `.private` measurably
helps depends on the GPU family, on whether the driver applies compression to
compute-written textures, and on the pixel format. It is cheap to try and cheap to
revert.

### Proposed change

- Add a `storage:` parameter to `ImageDecoder.makeTexture` and pass `.private` for the
  pyramid levels, pyramid scratch and MTF textures. No other code changes.
- Drop `.renderTarget` from the usage for textures that are never render targets, or
  keep it deliberately if it turns out to be what enables compression on the target
  family (document which, and why).
- The ping-pong pair is harder: `render` writes the input and reads back the result,
  so making those `.private` means a staging blit into a `.shared` texture or an
  `MTLBuffer`. Consider it only alongside [PERF-15](#perf-15), which would remove the
  readback entirely.

### Acceptance criteria

- Pyramid and MTF textures are `.private`; no CPU access path to them exists.
- Every golden image and the tiled/untiled equality test are unchanged.
- A measured before/after on device for one Preview frame's GPU time.

### How to verify

```sh
swift test -c release --filter 'golden|Bloom|Halation|MTF|aTiledExportReproducesTheUntiledRender'
```

On device: Instruments **Metal System Trace**, comparing per-kernel GPU time and the
"Memory Bandwidth" counter for the Bloom and Halation dispatches before and after.
If the difference is inside the noise, revert and record the result here.

---

<a id="perf-10"></a>
## PERF-10 — The Metal library is compiled from `.metal` source at every `Renderer()`

**Severity** Medium · **Confidence** Confirmed-from-source · **Effort** M · **Path** Launch

### What the code does today

```swift
// Renderer.swift:44-57
let url = Bundle.module.url(forResource: "Pipeline", withExtension: "metal", subdirectory: "Metal")!
let options = MTLCompileOptions()
if #available(macOS 15, iOS 18, *) { options.mathMode = .safe }
else { options.fastMathEnabled = false }
let library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: options)
var pipelines: [String: any MTLComputePipelineState] = [:]
for name in [...21 names...] {
    guard let function = library.makeFunction(name: name) else { throw ... }
    pipelines[name] = try device.makeComputePipelineState(function: function)
}
```

`Pipeline.metal` ships as a **copied resource**, not as a compiled target:
`Package.swift:10` declares `resources: [.copy("Metal"), ...]`, and
`FilmApp.xcodeproj/project.pbxproj` contains no occurrence of the string `metal` at
all — there is no `CompileMetalFile` build phase and no `.metallib` anywhere in the
build.

So 639 lines of MSL are compiled from source, and 21 compute pipeline states are
built, at every `Renderer()` — and the app builds up to three Renderers: the Preview
one (`EditorModel.swift:152`), the thumbnail one (`EditorModel.swift:510`) and the
Contact Sheet's (`ContactSheetView.swift:66`).

`docs/audits/photo-open-responsiveness.md` records **42.3 ms for the first instance
and 2.6 ms for later ones on an Apple M1 Pro** (cited, not measured here). The gap is
the driver's source-hash binary cache, which is warm after the first compile but cold
on first launch after every install and every app update.

### Why it costs

First-photo latency on a cold shader cache, on a phone CPU rather than an M1 Pro. The
prior audit moved this off the main actor via `Renderer.make()`
(`Renderer.swift:62-64`) so it no longer *blocks* the UI, but it is still serialised
ahead of the first render — and, per [PERF-17](#perf-17), ahead of the Photos
transfer as well.

### Proposed change

- Compile `Pipeline.metal` at build time into a `.metallib` and load it with
  `device.makeDefaultLibrary(bundle:)` or `makeLibrary(URL:)`. For the Xcode app
  target this is a Compile Sources build phase; for SwiftPM it is a build-tool plugin
  invoking `xcrun -sdk … metal`/`metallib`. Keep the `.metal` source in the package
  for the ProfileBaker and the tests, or ship both.
- Preserve the math mode. `mathMode = .safe` must be passed to the offline compiler
  (`-fno-fast-math`) or the golden images and the identity bit-exactness test will
  move. That is the acceptance criterion below.
- Consider `MTLBinaryArchive` for the 21 pipeline states as a second step, once the
  library is precompiled.

### Acceptance criteria

- No `makeLibrary(source:)` call remains on the app's render path.
- `identityColourCubePreservesEveryFiniteHalfValue` and every golden image are
  bit-identical before and after, proving the math mode survived.
- First-photo time on a device with a purged shader cache (fresh install) improves
  measurably; record the before/after.

### How to verify

```sh
swift test -c release --filter 'identityColourCube|golden|tetrahedraMatchAnalyticalMinimum'
DYE_PHOTO_OPEN_AUDIT=1 swift test -c release --filter photoOpenAudit
```

The harness already prints `init_main_actor_ms` per instance
(`Tests/FilmEngineTests/PhotoOpenAuditTests.swift:34-36`), which is the exact number
this change targets. On device, delete and reinstall the app between runs so the
driver's shader cache is cold, and trace with Instruments **App Launch**.

---

<a id="perf-11"></a>
## PERF-11 — The render `Plan` — including the MTF fit — is rebuilt for every Tile

**Severity** Medium · **Confidence** Confirmed-from-source · **Effort** S · **Path** Both

### What the code does today

`renderTile` builds a fresh `Plan` on every call:

```swift
// Renderer.swift:146-147
let plan = try plan(profile: profile, settings: settings, frame: frame, tile: input,
                    spatial: spatial, grainModel: grainModel)
```

and `renderTiles` calls `renderTile` once per Tile (`Export.swift:80-81`). `plan()`
does real work each time:

- **The MTF fit** (`Renderer.swift:611-658`) is a least-squares solve whose
  `response(_:_:)` helper sums a truncated Gaussian per point per sigma. The coarse
  radius can be 24 (`Renderer.swift:629`), so that is up to 49 `exp` and `cos`
  evaluations per point, per sigma, per channel, on every call.
- **The Grain Density Response table** (`Renderer.swift:575-597`) builds 96 `Float`s,
  and for a Profile with `measuredDensityCurves` does a linear
  `curve.firstIndex { $0.density >= density }` scan per entry.
- **The Scatter level split** (`Renderer.swift:747-778`) and the **Geometry hash**
  (`Renderer.swift:661-677`).
- **Four `responseEntry` lookups** with a linear scan of the cache
  (`Renderer.swift:947`).

Every one of those depends on the *frame*, not on the Tile. `plan()`'s own doc comment
says so: "Sizes come from `frame`, never from `tile` … `tile` is consulted only for
how deep a Scattering Pyramid will fit in it" (`Renderer.swift:403-406`). Since every
Tile is rendered at the same padded size (`TilePlan.swift:12`), even that one
dependency is constant across an Export.

`tiling()` (`Renderer.swift:524-530`) then builds a *fifth* Plan for the same frame
before the loop starts, and `tilePlan()` calls it again (`Export.swift:55`).

### Why it costs

At 768 Tiles ([PERF-01](#perf-01)) the MTF fit runs 768 times for one Export, and the
Grain table is rebuilt 768 times. On the Preview path it runs on every frame of every
dial drag.

**Unverified**: what fraction of a frame this is. It is pure CPU on the actor, so it
adds directly to the actor-blocking window in [PERF-05](#perf-05), and it is trivially
removable either way.

### Proposed change

- Split `Plan` into a frame-invariant part and the per-Tile `Frame` uniform (which is
  already passed separately, `Renderer.swift:155`, `Export.swift:78-79`). Build the
  invariant part once in `renderTiles` and pass it to `renderTile`.
- Reuse the Plan `tiling()` already built rather than building another
  (`Export.swift:55`, `:67`).
- On the Preview path, cache the Plan keyed by `(profile.cacheID, settings, width,
  height)` — the Preview re-renders the same dimensions with one changed setting on
  every frame, so most of the Plan is identical between frames.
- Make `responseCache` a dictionary keyed by `(cacheID, name)` with a separate
  recency list, rather than a linear scan.

### Acceptance criteria

- One `plan()` call per Export, not one per Tile plus two.
- `aTiledExportReproducesTheUntiledRenderOfTheSameFrame` still passes at
  `apronFraction: 1` with max difference exactly 0.
- Every golden image is unchanged.

### How to verify

```sh
swift test -c release --filter 'aTiledExportReproducesTheUntiledRender|MTF|Grain|golden'
```

Add a debug counter on `plan()` and assert it is 1 for a multi-Tile Export. On device,
Instruments **Time Profiler** with the export running: `Renderer.mtf(profile:width:height:)`
should disappear from the profile.

---

<a id="perf-12"></a>
## PERF-12 — `ImageWriter` quantises scalar in `Double` on the renderer actor

**Severity** Medium · **Confidence** Likely · **Effort** S · **Path** Export

### What the code does today

```swift
// ImageWriter.swift:47-67
pixels.withUnsafeMutableBytes { raw in
    for row in 0..<tileHeight {
        ...
        for column in 0..<tileWidth {
            let alpha = min(max(Double(rgba[source + column * 4 + 3]), 0), 1)
            for channel in 0..<4 {
                let value = Double(rgba[source + column * 4 + channel]) * (channel == 3 ? 1 : alpha)
                let quantised = (min(max(value, 0), 1) * maximum).rounded()
                ...
                raw.storeBytes(of: UInt8(quantised), toByteOffset: index, as: UInt8.self)
```

One `Float16 → Double → clamp → multiply → round → UInt8/UInt16` chain per component,
with an unaligned `storeBytes` per component. **Derived**: 195 million iterations for
a 48 MP frame.

This runs inside the `sink` closure that `renderTiles` calls
(`Export.swift:86`), which is on the renderer actor — so it is added directly to the
window in which the Preview cannot run ([PERF-05](#perf-05)).

The same shape appears in `exportedPixels` (`Export.swift:35-38`), which copies a Tile
into the frame one `Float16` at a time instead of using a row `memcpy`. That path is
tests-and-diagnostics only (`Export.swift:26-27`), so it is lower priority, but it is
the same fix.

### Why it costs

`Double` is the widest arithmetic on the path and buys nothing: the source is
`Float16`, the destination is 8 or 16 bits. `UInt8(quantised)` is a trapping
conversion, so the clamp cannot be elided.

### Proposed change

- Do the quantise in `Float`, hoist the branch on `eightBit` out of the loop into two
  specialised loops, and write whole rows with `UnsafeMutableRawBufferPointer`
  arithmetic rather than per-component `storeBytes`.
- Better: use vImage. `vImageConvert_PlanarFtoPlanar8` / `_16U` over an interleaved
  buffer, or `vImageConvert_RGBA16FtoRGBA8888`, handles clamp, scale and round in one
  vectorised call. The premultiply can be a separate
  `vImagePremultiplyData_RGBAFFFF`.
- Move the call off the renderer actor: `renderTiles` could hand the Tile's core to a
  detached task and only await it before the next Tile needs the buffer.

### Acceptance criteria

- `writersProduceTaggedFilesInEveryFormat` and `sRGBAndDisplayP3DifferOnlyInPrimaries`
  pass unchanged.
- Written bytes are **bit-identical** to today's for a fixed input in all three
  formats — rounding must not move. Capture a fixture first.
- `ImageWriter.write` no longer appears on the renderer actor's critical path.

### How to verify

```sh
swift test -c release --filter 'writersProduceTaggedFiles|sRGBAndDisplayP3DifferOnly|ExportDate'
```

On device, Instruments **Time Profiler** during a 48 MP Export: `ImageWriter.write`
should fall from a visible share of the export to noise.

---

<a id="perf-13"></a>
## PERF-13 — Blur kernels recompute `exp()` per tap per pixel; library-wide safe math

**Severity** Medium · **Confidence** Needs measurement · **Effort** S · **Path** Both

### What the code does today

Both blurs build their Gaussian weights inside the per-pixel loop.

```metal
// Pipeline.metal:105-109  (Scattering Pyramid, 11 taps, run twice per level per pyramid)
for (int i = -SCATTER_BLUR_RADIUS; i <= SCATTER_BLUR_RADIUS; ++i) {
    float weight = exp(-0.5f * float(i * i) / (SCATTER_BLUR_SIGMA * SCATTER_BLUR_SIGMA));
```

`SCATTER_BLUR_SIGMA` is a compile-time `constant` (`Pipeline.metal:98`), so those 11
weights are the same for every pixel of every level of every pyramid in the app's
lifetime.

```metal
// Pipeline.metal:196-202  (MTF)
int radius = int(blur.radius);
for (int i = -radius; i <= radius; ++i) {
    float weight = exp(-0.5f * float(i * i) / (blur.sigma * blur.sigma));
    ...
}
output.write(half4(half3(sum / total), input.read(p).a), p);
```

The MTF radius is bounded at 24 (`Renderer.swift:629`), so the coarse Gaussian can be
49 taps. Two Gaussians, two axes each, gives up to **196 `exp` evaluations and 196
texture reads per pixel** for the MTF Pass alone (**derived** from
`Renderer.swift:627-629` and `Pipeline.metal:199`). Line 204 also issues an extra
`input.read(p)` purely to fetch alpha, after already having read the whole
neighbourhood.

Separately, `MTLCompileOptions.mathMode = .safe` (`Renderer.swift:46`) applies to the
whole library, which means `exp`, `log10`, `pow` and division are all precise
everywhere — including `transfer`/`inverseTransfer` (`Pipeline.metal:480-489`), which
the Adjustment Pass calls six times per pixel (`Pipeline.metal:556-558`) and the
Output Transform three times (`Pipeline.metal:638`).

### Why it costs

Safe math is a deliberate and correct choice — `identityColourCubePreservesEveryFiniteHalfValue`
and the golden images depend on it, and it must not be turned off wholesale. But it
raises the price of every transcendental, which makes recomputing 196 of them per
pixel a worse deal than it would otherwise be.

**Unverified**: whether the MTF Pass is actually a measurable share of a frame. It is
one of about fifty dispatches, but it is the one with by far the highest ALU count per
pixel.

### Proposed change

- **Precompute the weights on the CPU.** Both the Scattering blur (fixed sigma) and
  the MTF blur (sigma known when the Plan is built, `Renderer.swift:656-657`) can pass
  a normalised weight array in a `constant float*` buffer, exactly as the MTF
  coefficients already are (`Pipeline.metal:214`, `Renderer.swift:876`). This removes
  every `exp` from both inner loops and the `total` accumulation with it, and cannot
  change results if the CPU-side sum uses the same order and precision — which must be
  asserted, not assumed, against the golden images.
- **Drop the redundant alpha read** at `Pipeline.metal:204` by carrying alpha from the
  `i == 0` tap.
- **Consider threadgroup-memory tiling** for the separable blurs: at 49 taps the MTF
  pass re-reads each texel up to 49 times. This is a larger change and should follow
  the weight precompute, not precede it.
- **Do not change the library math mode.** If a specific kernel is shown to be
  transcendental-bound, use `fast::exp` at that call site alone and prove the golden
  images are unchanged.

### Acceptance criteria

- No `exp()` remains in `scatterBlur` or `mtfBlur`.
- `mathMode = .safe` is still set for the library.
- Every golden image, `identityColourCubePreservesEveryFiniteHalfValue`, and the
  MTF tests are bit-identical.
- Measured GPU time for the `mtf.*` and `*.blur*` dispatches falls; record by how much.

### How to verify

```sh
swift test -c release --filter 'MTF|Bloom|Halation|golden|identityColourCube'
```

On device: Instruments **Metal System Trace**, per-encoder GPU time for the labelled
`mtf.fine.h`, `mtf.coarse.v`, `bloom.blurH.*` and `halation.blurV.*` encoders (the
labels already exist, `Renderer.swift:827-830`, `:865`).

---

<a id="perf-14"></a>
## PERF-14 — `.id(model.selectedStock)` tears down the Metal canvas on every Stock change

**Severity** Medium · **Confidence** Confirmed-from-source · **Effort** S · **Path** Preview

### What the code does today

```swift
// EditorView.swift:124-129
private var photoCanvas: some View {
    CanvasView(content: canvas, isComparing: isComparing, ...)
        .id(model.selectedStock)
```

`.id()` gives the subtree a new identity whenever the Stock changes, which destroys
and rebuilds `CanvasView`, `FilmCanvas`, the `MTKView` and its `CAMetalLayer`, and the
`Coordinator` — discarding `Coordinator.texture` and `Coordinator.queue`
(`FilmCanvas.swift:50`, `:53`) and forcing a fresh drawable pool and a fresh 24 MB
texture upload (`FilmCanvas.swift:87-98`).

The prior audit's fix to share the display pipeline survives this
(`FilmCanvas.swift:49`, `:84`: `sharedPipeline` is `static`), so the shader is not
recompiled. Everything else is.

Separately, each `Coordinator` creates its own command queue:

```swift
// FilmCanvas.swift:86
if queue == nil { queue = device.makeCommandQueue() }
```

With the filmstrip sheet open there are 18 cells each hosting a `FilmCanvas`
(`Filmstrip.swift:117-142`) in a plain `HStack`, not a `LazyHStack`
(`Filmstrip.swift:52`), plus the main canvas and up to two Output Stage cards
(`OutputStageCards.swift:21`) — about 21 live `MTLCommandQueue` objects and 21
`CAMetalLayer`s, each with its own drawable pool.

### Why it costs

Stock switching is the app's signature interaction and the one most likely to be done
rapidly. Recreating a `CAMetalLayer` involves surface allocation and a first-frame
path that is measurably slower than a redraw.

The prior audit's canvas work concluded that "unchanged canvases do not redraw"; this
`.id()` defeats that for the one canvas that matters, whenever the Stock changes.
**Unverified**: whether the `.id()` is load-bearing for some reset that is not obvious
from the source — it should be removed only after checking what state it was added to
clear.

### Proposed change

- Remove `.id(model.selectedStock)` and reset whatever state motivated it explicitly
  (`onChange(of: model.selectedStock)`), the way `CanvasView` already resets the loupe
  and drag (`CanvasView.swift:96-98`).
- Hoist the command queue to a `static` shared per device, as `sharedPipeline` already
  is. All canvases use the system default device (`FilmCanvas.swift:48`), so one queue
  serves them all.
- Make the filmstrip's `HStack` a `LazyHStack` (`Filmstrip.swift:52`) so only visible
  cells hold a Metal surface. Prior audit called this out as "a separate measured
  change"; it is still not done.

### Acceptance criteria

- Changing the Stock does not construct a new `FilmCanvas.Coordinator` (assert with a
  debug counter or an `os_signpost` in `makeCoordinator`).
- At most one `MTLCommandQueue` exists per Metal device for display.
- With the filmstrip open on an 18-Stock Catalogue, the number of live `CAMetalLayer`s
  is bounded by what is on screen.
- Compare, loupe and resize behaviour is unchanged.

### How to verify

Instruments **Time Profiler** and **Core Animation**, tapping through six Stocks in
the filmstrip: measure time from tap to first presented frame, before and after.
`CAMetalLayer` count is visible in the **Allocations** instrument.

---

<a id="perf-15"></a>
## PERF-15 — Every Preview frame round-trips 24 MB through the CPU to reach the canvas

**Severity** Medium · **Confidence** Likely · **Effort** L · **Path** Both

This is item 2 of the prior audit's "Remaining opportunities"
(`docs/performance-audit.md`) and it is **still open**. It is restated here with
current line references because it is the largest structural cost left on the Preview
path, and because [PERF-09](#perf-09) partly depends on it.

### What the code does today

The renderer reads the result texture back into a Swift array:

```swift
// Renderer.swift:935-943
let rgba = [Float16](unsafeUninitializedCapacity: count) { buffer, initialized in
    texture.getBytes(buffer.baseAddress!, bytesPerRow: texture.width * 8,
                     from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
```

That array becomes `RenderedPixels.rgba` (`RenderTypes.swift:316-322`),
crosses to the main actor (`EditorModel.swift:564`), and is uploaded back into a
fresh `MTLTexture` in the canvas (`FilmCanvas.swift:87-98`).

**Derived**, at 2048 × 1536: 24 MB down and 24 MB up, per frame, plus a 24 MB texture
allocation per distinct `RenderedPixels.id`.

The prior audit's fix means the *upload* is skipped when pixels have not changed
(`FilmCanvas.swift:87`, keyed on `image.id`) — but during a dial drag every frame has
new pixels, so every frame pays both directions.

### Why it costs

Two full-surface copies and one texture allocation per frame, on the actor and on the
main actor respectively. At 120 Hz that is 5.7 GB/s of pure copy traffic if the
renderer could keep up, which it cannot — but it is a floor under the frame time
either way.

The prior audit also notes this is what would allow the retained-texture question to
be answered properly. **Unverified**: what share of a Preview frame this is.

### Proposed change

Hand the canvas a texture rather than an array. Have `Renderer` return an opaque
`RenderedFrame` holding the result `MTLTexture` (plus its `id`, `width`, `height` and
`output`), and have `FilmCanvas` sample it directly. This requires:

- explicit ownership so the renderer does not overwrite a texture the canvas is still
  presenting — a small ring of result textures, or a per-frame `.private` texture the
  canvas takes ownership of;
- synchronisation between the render command buffer and the canvas's draw, via a
  shared `MTLEvent` or by presenting from the same queue;
- keeping `RenderedPixels` for the paths that genuinely need CPU pixels — Export
  (`ImageWriter`), `exportedLUT`, the tests and the golden images. Both should exist.

This is an L because it changes the engine's public boundary, which is one of the
project's three declared Test Seams (`CONTEXT.md`, *Test Seam*). It should be added
alongside `RenderedPixels`, not in place of it.

### Acceptance criteria

- The Preview path performs zero `getBytes` and zero `replace` per frame.
- `Renderer.render` returning `RenderedPixels` still exists and is still the test
  seam; every existing renderer test passes unchanged.
- Compare (hold-to-compare shows `beforePixels`) and the loupe still work, including
  reusing an already-presented frame for loupe-only movement.
- No visual tearing under a sustained dial drag.

### How to verify

```sh
swift test -c release --filter 'repeatedPreviewRendersMatchFreshRenderers|golden|identityColourCube'
```

On device, Instruments **Metal System Trace** plus **Core Animation FPS**: dial-drag
frame pacing on both a 60 Hz and a 120 Hz iPhone, before and after. This is also
prior-audit item 3, which remains unmeasured.

---

<a id="perf-16"></a>
## PERF-16 — `exportedLUT` formats the file with `String(format:)` per component

**Severity** Low · **Confidence** Confirmed-from-source · **Effort** S · **Path** Export

```swift
// ExportedLUT.swift:62-65
for entry in 0..<(size * size * size) {
    let index = entry * 4
    lines.append((0..<3).map { String(format: "%.6f", Double(rendered.rgba[index + $0])) }.joined(separator: " "))
}
```

**Derived**: at the default `size: 33` (`ExportedLUT.swift:24`) that is 35 937 entries
× 3 = **107 811** `String(format:)` calls, each bridging through `CVarArg` and
`NSString`, plus 35 937 intermediate arrays and 35 937 `joined` strings, then one more
`joined` over the lot. At the maximum `size: 65` it is 823 875 calls.

The whole thing runs on the renderer actor (`Renderer.exportedLUT` is an actor
method), so it blocks the Preview for its duration — see [PERF-05](#perf-05). The
doc comment at `EditorModel.swift:357-358` says a LUT export is "quick enough not to
need progress or cancelling", which is a claim this code makes riskier than it needs
to be.

**Proposed change**: format with a fixed-point integer path
(`Int((value * 1e6).rounded())` split into whole and fractional parts) written into a
preallocated `[UInt8]`, or at minimum hoist to one `String(format:)` per line with
three arguments and reserve the output string's capacity. Build the text off the
actor: only the lattice render needs the Renderer.

**Acceptance criteria**: `theExportedLUTMatchesTheRenderWithGrainAndHalationAtZero`
(`Tests/FilmEngineTests/ExportTests.swift:327`) passes and the emitted file is
**byte-identical** to today's for a fixed Profile and settings; `exportedLUT` no
longer holds the renderer actor while formatting.

**How to verify**: `swift test -c release --filter 'theExportedLUTMatches|parseCube'`,
plus a byte-comparison against a captured fixture.

---

<a id="perf-17"></a>
## PERF-17 — Renderer construction is serialised ahead of the Photos transfer

**Severity** Low · **Confidence** Confirmed-from-source · **Effort** S · **Path** Preview

```swift
// EditorModel.swift:152-153
if renderer == nil { renderer = try await Renderer.make() }
guard let data = try await item.loadTransferable(type: Data.self), let renderer else {
```

The renderer build and the Photos transfer are independent, and both are slow: the
build is a Metal library compile ([PERF-10](#perf-10)), and the transfer can involve
an iCloud download. They run one after the other.

**Proposed change**:

```swift
async let renderer = self.renderer ?? Renderer.make()
async let data = item.loadTransferable(type: Data.self)
```

then await both. Keep the request-generation guard (`EditorModel.swift:146-149`,
`:157`) and the cancellation checks intact; the failure modes of the two must stay
distinguishable in the error message.

**Acceptance criteria**: time from selection to first published `beforePixels` falls
by approximately the smaller of the two durations on a cold shader cache; error
messages still distinguish "Metal is unavailable" from "The photo could not be
loaded"; rapid A→B selection still cancels correctly.

**How to verify**: `DYE_PHOTO_OPEN_AUDIT=1 swift test -c release --filter photoOpenAudit`
gives the engine-side baseline. The UI-side interval needs the on-device signpost
trace that `docs/audits/photo-open-responsiveness.md` already asks for and that
remains uncaptured.

---

<a id="perf-18"></a>
## PERF-18 — Contact Sheet builds a third Renderer and re-reads the Catalogue per open

**Severity** Low · **Confidence** Confirmed-from-source · **Effort** S · **Path** Preview

```swift
// ContactSheetView.swift:63-74
profiles = try await Task.detached { [.identity] + (try ProfileCatalogue.bundled().profiles) }.value
let renderer = try await Renderer.make()
let input = try await Task.detached { try ContactSheetReference.image() }.value
for profile in profiles { ... images[profile.id] = pixels }
```

Both the Catalogue read and the renderer build are off the main actor — the prior
audit's fix is present and correct. What is not fixed is that all of it is thrown away
when the sheet is dismissed and repeated on the next open: a third Metal library and
21 pipeline states ([PERF-10](#perf-10)), 18 profile headers re-read and re-decoded
(**cited**: 6.6 ms for 17 Profiles on an M1 Pro,
`docs/audits/photo-open-responsiveness.md`), and a full Catalogue sweep of Colour
Cubes against a four-entry cache — about 53.6 MB (**derived**, see
[PERF-04](#perf-04)).

The Reference itself is 192 × 128 (`ContactSheetReference.swift:9`), so the pixel work
is trivial; the cost is entirely Catalogue and cube residency.

The editor already holds a loaded Catalogue (`EditorModel.catalogue`,
`EditorModel.swift:13`) and a spare Renderer (`thumbnailRenderer()`,
`EditorModel.swift:508-514`). The Contact Sheet does not take
`EditorModel` — only `selectedStock` (`ContactSheetView.swift:12`) — which is a clean
boundary worth keeping, so pass the Catalogue and a renderer provider in rather than
passing the model.

**Acceptance criteria**: opening the Contact Sheet a second time constructs no new
Renderer and reads no `.filmprofile` bytes; the sheet still renders correctly when
opened before the editor's Catalogue has loaded.

**How to verify**: Instruments **File Activity** and **Allocations** across two
Contact Sheet opens; assert `MTLLibrary` count does not grow.

---

<a id="perf-19"></a>
## PERF-19 — 210 MB Catalogue in the bundle; one Stock is 79 MB of it

**Severity** Low · **Confidence** Confirmed-from-source · **Effort** M · **Path** Launch

`Package.swift:10` copies the whole `Catalogue` directory into the bundle. Reading the
container headers (`ProfileContainer.swift:73-80`) of every file gives, **derived**:

| Stock | File | `lutSize` | Largest payload |
| --- | --- | --- | --- |
| cinestill-800t | 79.7 MB | **129** | 16.4 MB |
| vision3-500t | 19.8 MB | 65 | 2.10 MB |
| portra-400 / 160, vision3-50d/200t/250d | 19.8 MB each | 65 | 2.10 MB |
| provia-100f | 11.0 MB | 65 | 2.10 MB |
| velvia-50 | 8.8 MB | 65 | 2.10 MB |
| studies (×3) | 0.58 MB each | 33 | 0.29 MB |
| monochrome (×4) | ≤ 18 KB each | 33 | 2 KB |
| **Total** | **210 MB** | | |

Two consequences. First, the app's download and on-disk size is dominated by the
Catalogue, and 38 % of it is one Stock. Second, Cinestill's 129³ cubes cost **8× the
Colour Cube cache, the file read, the `[Float16]` decode and the 3D texture upload of
every other Stock** ([PERF-04](#perf-04)), which is why it is the worst case for every
Stock-switch and Development Offset hitch in this document.

`README.md` states that Cinestill "ships byte-identical Colour Cubes" to Vision3 500T.
The headers do not agree: 500T's `lutSize` is 65 and Cinestill's is 129, and their
payload lengths differ by 8×. That is an accuracy/provenance question rather than a
performance one and belongs to whoever owns `docs/audits/film-stock-accuracy.md` — but
if the two really are meant to carry the same data, the 79 MB file and its 8× runtime
cost are both avoidable, which is why it is noted here.

**Proposed change**: establish whether 129³ is required for Cinestill or is a bake
artefact. If it is required, keep it and size the cube cache in bytes
([PERF-04](#perf-04)) so one Stock cannot evict four others. If it is not, re-bake at
65³ and reclaim 69 MB of bundle and 8× of its runtime cost. Independently, consider
On-Demand Resources or App Thinning for the Catalogue so a first install does not
carry every Stock.

**Acceptance criteria**: the `lutSize` discrepancy between `cinestill-800t` and
`vision3-500t` is either justified in `Curves/cinestill-800t/SOURCES.md` or removed;
if removed, every Cinestill golden image is re-reviewed through the explicit
[golden-image update workflow](../golden-images.md).

**How to verify**: `swift test -c release --filter 'golden|ProfileCodec'` after any
re-bake, and a bundle-size comparison from the built `.app`.

---

<a id="perf-20"></a>
## PERF-20 — SwiftData container is created synchronously at launch

**Severity** Low · **Confidence** Needs measurement · **Effort** S · **Path** Launch

```swift
// FilmApp.swift
var body: some Scene { WindowGroup { EditorView() }.modelContainer(for: Preset.self) }
```

`.modelContainer(for:)` opens or migrates the store on the main actor before the first
frame. This is item 6 of the prior audit's remaining list and is unchanged.

**Unverified, and deliberately so:** with an empty Preset store this is almost
certainly negligible, and the prior audit correctly declined to change it without a
measurement. The measurement that settles it is a cold launch with a large Preset
store, which nobody has taken.

**How to verify**: seed a store with several hundred Presets, then Instruments **App
Launch** on device, looking at main-thread time attributed to `ModelContainer` before
first frame. If it is under a few milliseconds, close this item permanently and say so
here. If it is not, move the container behind an `async` load with a placeholder
scene.

---

## Verification backlog

Everything below needs a Mac with Xcode, and the device items need a physical iPhone.
None of it can be done in this environment. Ordered by what would change the most
decisions.

### 1. On-device 48 MP Export — settles PERF-01, PERF-02, PERF-05, PERF-06

The single most important measurement in this document. `docs/export.md:159-163`
records 13.0 s on an Apple Silicon Mac; nothing is known about a phone, and
`README.md` already says a simulator does not reproduce the memory pressure.

```
Instruments → Metal System Trace + Allocations + VM Tracker + Thermal State
Device: smallest-memory supported iPhone, and a current Pro
Input: 48 MP ProRAW and a 24 MP import, through Cinestill 800T at default settings
Record: wall-clock; peak resident bytes; whether a jetsam event occurs;
        thermal state over time; GPU utilisation; TilePlan.count and isApronCapped
```

Also log `os_proc_available_memory()` at Export start, after decode, after the first
Tile and before `writer.encode` — four cheap numbers that would settle PERF-02 alone.

### 2. Preview frame budget under a dial drag — settles PERF-08, PERF-09, PERF-13, PERF-15

`docs/performance-audit.md` records warm Portra 400 Preview renders at 20.7–21.0 ms on
an Apple Silicon Mac and states plainly that "full-quality preview rendering is not
proven to meet a 16.7 ms frame budget, much less an 8.3 ms budget". That is still the
state of knowledge.

```
Instruments → Metal System Trace + Core Animation FPS
Device: a 60 Hz iPhone and a 120 Hz iPhone
Action: sustained Exposure drag, sustained Halation drag, rapid Stock switching
Record: per-encoder GPU time (the labels already exist: bloom.*, halation.*, mtf.*,
        grain.*, filmResponse, densityOutput, adjust, geometry, outputTransform);
        CPU encode time per frame; getBytes and replace time; dropped frames
```

The per-encoder breakdown is what decides whether PERF-13 (MTF ALU) or PERF-15
(readback) is the better first move.

### 3. Catalogue sweep cost — settles PERF-03, PERF-04, PERF-18

```
Instruments → Time Profiler + File Activity
Action: open the filmstrip sheet twice; open the Contact Sheet twice
Record: time per sweep; bytes read from *.filmprofile per sweep;
        time in responseEntry, decodeHalfValues, makeColourCube
```

A second sweep reading zero profile bytes is the acceptance criterion for PERF-04.

### 4. Cold-launch and first-photo path — settles PERF-10, PERF-17, PERF-20

```sh
DYE_PHOTO_OPEN_AUDIT=1 swift test -c release --filter photoOpenAudit
```

gives the engine baseline on a Mac (`init_main_actor_ms`, `preview_decode_ms`,
`before_ms`, `thumbnail_decode_ms`, `edited_ms`, `dial_warm_mean_ms`). On device:

```
Instruments → App Launch + Hangs, on a freshly installed build (cold shader cache)
Record: time to first frame; time from photo selection to first presented render;
        main-thread time in ModelContainer; whether Renderer.make overlaps the
        Photos transfer
```

`docs/audits/photo-open-responsiveness.md` already specifies the signpost timeline
this needs and it has still not been captured. It is the only way to attribute the
reported before-picker delay.

### 5. Storage-mode experiment — settles PERF-09

Change the pyramid and MTF textures to `.private`, run the golden images, and compare
per-encoder GPU time in a Metal System Trace. If the difference is inside the noise,
revert and record that here so nobody tries it again.

### 6. Regression gates worth adding

```sh
# already exist and should stay green through every change above
swift test -c release --skip 'bakerCLI|everyCurveSet|bakerRejects|portraCLI|spectralValidation|portraDevelopment|portraChromatic|spectralCLI|aDerivedStock|aMonochromeCurveSet|theMonochromeCollapse'
```

New gates this audit implies:

- A checked-in `TilePlan` table for 4032 × 3024, 4500 × 3375, 6000 × 4000 and
  8064 × 6048, asserting Tile count and `isApronCapped`, so the cliff in PERF-01
  cannot come back silently.
- A payload-read counter on `Profile`, asserted to be zero on a second Catalogue
  sweep (PERF-04).
- A `plan()` call counter, asserted to be 1 per Export (PERF-11).
- A byte-identity fixture for `ImageWriter` output and for `exportedLUT` text, so
  PERF-12 and PERF-16 can be optimised without changing a single output byte.

---

## Confirmed healthy

Checked and found already correct. **Do not re-audit these.**

**Every fix from the 2026-09-09 audit is present in `c19bc12`**, with two partial
exceptions noted below.

- **Async renderer factory.** `Renderer.make()` exists (`Renderer.swift:62-64`) and
  every production call site uses it: `EditorModel.swift:152`, `EditorModel.swift:510`,
  `ContactSheetView.swift:66`. The three remaining synchronous `try Renderer()` calls
  (`EditorView.swift:260`, `Filmstrip.swift:176`, `ExportSheet.swift:280`,
  `ContactSheetView.swift:221`) are all inside `#Preview` helper views and do not ship.
- **Shared display pipeline.** `FilmCanvas.Coordinator.sharedPipeline` is `static`
  (`FilmCanvas.swift:49`, `:84`), so the canvas shader is compiled once per process
  rather than once per canvas.
- **Canvas redraw elision.** `updateUIView` returns early when neither the pixel
  identity nor the loupe changed (`FilmCanvas.swift:39`), and the texture is reused
  across draws while `image.id` is unchanged (`FilmCanvas.swift:87-98`).
  `RenderedPixels.id` gives rendered pixels stable identity (`RenderTypes.swift:318`).
  Loupe-only movement genuinely does not re-upload.
- **Dial texture reuse.** `previewTextures` is retained and refilled rather than
  reallocated while dimensions are unchanged (`Renderer.swift:19`, `:84-92`), and
  copy-only Passes are skipped without swapping the ping-pong textures
  (`Renderer.swift:206`), which is what makes the skip safe.
- **Passes that resolve to nil release their resources.** `pyramids[scattering] = nil`
  and `mtfTextures = nil` when the Plan drops those Passes
  (`Renderer.swift:166`, `:174`) — so a Stock or an intensity that does not use them
  does not keep 88 MB alive.
- **Off-main-actor Catalogue loads.** `EditorModel.loadCatalogue` and
  `ContactSheetView.load` both use `Task.detached`
  (`EditorModel.swift:141`, `ContactSheetView.swift:65`), and `loadCatalogue` returns
  early if already loaded (`EditorModel.swift:140`).
- **Export file writes are off the UI actor,** with cancellation cleanup
  (`EditorModel.swift:416-432`).
- **Request-generation ownership on photo open.** `openGeneration` guards every
  publication and the loading-flag cleanup (`EditorModel.swift:146-149`, `:157`,
  `:162`, `:180`, `:185`), obsolete thumbnail and Preset jobs are cancelled
  (`:163-164`), and the Preview is published before the thumbnail decode (`:166-176`
  before `:178`).
- **Full elapsed render duration.** `Self.seconds(since:)` keeps whole seconds
  (`EditorModel.swift:411-414`, used at `:566`).
- **Unchanged assignments are ignored.** Both `selectedStock` and `settings` compare
  against `oldValue` before scheduling (`EditorModel.swift:14-15`), and stock
  constraints are applied in one settings write (`EditorModel.swift:189-193`).
  *Partial:* `stockChanged()` then calls `scheduleRender()` again at
  `EditorModel.swift:194` after the `settings` assignment has already fired it —
  folded into [PERF-04](#perf-04)'s acceptance criteria.
- **Latest-value render coalescing.** The `needsRender` loop
  (`EditorModel.swift:550-572`) renders the latest settings rather than every
  intermediate, and drops results whose `imageGeneration` has moved on (`:559`, `:563`).
- **Thumbnail debounce and cancellation.** 200 ms debounce and per-item cancellation
  checks (`EditorModel.swift:526`, `:532`, `:542`); one failing Profile does not stop
  the rest (`:540-541`).
- **`OutputStageCards` invalidation is correctly keyed** on
  `(thumbnailGeneration, selectedStock, settings-without-outputStage)`
  (`OutputStageCards.swift:45`, `:66-72`), so selecting a stage does not invalidate
  either card.
- **Export runs on its own command queue** (`Renderer.swift:9-11`, `:41-42`,
  `Export.swift:81`, `:102`), yields between Tiles, and sleeps 50 ms per Tile when
  throttling (`Export.swift:92`). Cancellation is checked per Tile
  (`Export.swift:75`). One Export at a time is enforced (`EditorModel.swift:300`).
  The blocking problem is *within* a Tile ([PERF-05](#perf-05)), not between them.
- **`decodeHalfValues` is already optimised** — one copy, then a word-parallel
  non-finite check rather than a per-element traversal
  (`ProfileContainer.swift:135-169`), with an explicit comment saying why.
- **`ProfileContainer.load` reads headers only,** leaving payloads on disk until asked
  for (`ProfileContainer.swift:60-71`, `Profile.swift:40-55`). Catalogue loading does
  not touch a single Colour Cube.
- **RAW decode is correctly confined and correctly synchronised** — Core Image renders
  straight into the Metal texture on an explicit command buffer rather than a nil one,
  with `cacheIntermediates: false` and every photographic boost disabled
  (`ImageDecoder.swift:18`, `:29-58`). The RAW path does *not* have PERF-02's Float32
  staging problem.
- **Grain and Geometry read frame-global coordinates,** not Tile-local ones
  (`Pipeline.metal:413`, `:439`, `:599`, `Renderer.swift:880-882`), which is what makes
  a Tile a window onto the untiled render.
- **The Adjustment Pass, Reciprocity Pass, White Balance, Exposure and the Output
  Stage all resolve to `passthrough` and are skipped entirely at neutral**
  (`Renderer.swift:922-933`, `:206`). Neutral controls genuinely cost nothing.
- **Tetrahedral Colour Cube sampling is minimal** — four texture reads and no
  branching beyond the three-element sort (`Pipeline.metal:226-242`) — and the
  Development Offset blend correctly costs a second set of four reads only when
  `blend.x > 0` (`Pipeline.metal:263`), so an exact Offset pays nothing for the blend.
- **The Monochrome branch bypasses Colour Cube sampling entirely** for a 1D Density
  Curve lookup (`Pipeline.metal:297-324`), which is both cheaper and more faithful.
- **Haptic generators are reused** (`FilmApp/Design/Haptics.swift`), as the prior audit
  found.
- **`ContactSheetPaper` uses `LazyVGrid`** (`ContactSheetView.swift:99`). It is the
  filmstrip's `HStack` that is not lazy ([PERF-14](#perf-14)).
