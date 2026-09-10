# Security and privacy audit

**Date:** 2026-09-10
**Commit audited:** `c19bc12` (`main`)
**Scope:** `Sources/FilmEngine` (engine, Profile codec, Metal `Pipeline.metal`, Export),
`FilmApp/` (SwiftUI app), `FilmApp.xcodeproj/project.pbxproj`, `Package.swift`,
`.github/workflows/`, `Scripts/`, `ProfileBaker/`. Vocabulary follows
[CONTEXT.md](../../CONTEXT.md).

## Method and limits

This was a **static source reading** performed on a Linux host with **no Swift
toolchain, no Xcode, no iOS device or simulator, no Metal device and no network
access**. Nothing was built, run, fuzzed or dynamically tested. Every finding below
cites a file and line that was actually read at `c19bc12`; nothing was inferred from
a build, a crash log or an instrument trace.

Where a conclusion depends on runtime behaviour I could not observe — whether
`CIRAWFilter` can be made to return a pathological extent, whether a real photograph
can drive a Working Space value past float16 range, what iOS actually does with the
temporary directory — the finding is marked **Needs testing** and carries the exact
test that would settle it. Two things I explicitly could *not* check: the built
`Info.plist` (it is generated, not tracked) and any behaviour of Apple's ImageIO,
Core Image and Photos frameworks beyond their documented contracts.

Severities reflect the threat model in the next section, not a generic web-app
rubric. **No Critical or High finding was identified.** The engine is in
noticeably good shape for its class; see [Confirmed healthy](#confirmed-healthy)
for the substantial list of things that were checked and found sound.

---

## Threat model

Dye is a **local, offline-first photo editor**. It has no accounts, no server, no
sync and — verified by grep across every shipping `.swift` file — **no networking
code of any kind**: no `URLSession`, no `WKWebView`, no sockets, no third-party SDK
(`Package.swift` declares zero external dependencies). There is therefore no
authentication, no transport security, no session management and no server-side
attack surface to audit, and this document does not pad itself with any.

What the app *is* exposed to:

1. **Untrusted photo bytes.** The one genuinely attacker-influenceable input. A
   hostile JPEG/PNG/HEIC/DNG arrives by Message or AirDrop, is saved to the photo
   library, and the user opens it in Dye. Those bytes reach
   `CGImageSourceCreateWithData` and `CIRAWFilter` **in-process**
   (`Sources/FilmEngine/ImageDecoder.swift:24,29`), then drive allocation sizes,
   loop bounds and texture dimensions. This is where a real memory-safety or
   denial-of-service bug would live.
2. **The user's own photographs, at rest.** Pixels, EXIF, GPS. The question is not
   whether they leave the device (nothing can send them) but where copies are
   *written* and how long they live.
3. **Profiles and Presets.** Audited carefully and then largely discharged: the
   `.filmprofile` codec is only ever fed from the signed app bundle
   (`ProfileCatalogue.bundled()`), and Presets are local SwiftData rows. See
   [Confirmed healthy](#confirmed-healthy).
4. **GPU memory safety.** Profile- and user-supplied numbers become dispatch sizes
   and array indices in `Pipeline.metal`. Audited in full; found sound.
5. **Developer tooling** — the Baker, `Scripts/`, CI. Never ships inside the app
   (CONTEXT.md, "Baker"), so a finding here costs a maintainer's laptop or a CI
   runner, not a user's phone. Weighted accordingly.

Out of scope by construction: network attackers, malicious other apps (no App
Groups, no shared container, no custom URL scheme, no pasteboard use), and App
Store submission paperwork (a separate audit covers that; SEC-05 below touches the
privacy manifest only where it is a *privacy-correctness* question).

---

## Summary

| ID | Title | Severity | Confidence | Effort | Category |
|----|-------|----------|------------|--------|----------|
| [SEC-01](#sec-01) | Decode bounds each dimension but not the pixel count, so a decompression bomb can exhaust memory on open and on Export | Medium | Confirmed-from-source (bound is absent); Needs testing (jetsam) | M | Input parsing |
| [SEC-02](#sec-02) | No finiteness invariant between decode and `ImageWriter`; a NaN pixel traps on `UInt8(_:)` | Low | Confirmed-from-source (trap is reachable if NaN occurs); Needs testing (whether NaN occurs) | S | Input parsing |
| [SEC-03](#sec-03) | Every successful Export leaves a full-resolution copy of the photo in the temporary directory forever | Medium | Confirmed-from-source | S | Privacy |
| [SEC-04](#sec-04) | RAW extent is converted to `Int` without a finiteness or range check | Low | Likely | S | Input parsing |
| [SEC-05](#sec-05) | No `PrivacyInfo.xcprivacy`, and the app target's Resources build phase is empty | Low | Confirmed-from-source | S | Privacy |
| [SEC-06](#sec-06) | CI actions are pinned to floating major tags rather than commit SHAs | Low | Confirmed-from-source | S | Supply chain |
| [SEC-07](#sec-07) | Profile `id` becomes a filename component with no path sanitisation | Informational | Confirmed-from-source | S | Platform hardening |
| [SEC-08](#sec-08) | Metal shader source ships as a bundle text resource and is compiled at runtime | Informational | Confirmed-from-source | M | Platform hardening |

---

<a id="sec-01"></a>
## SEC-01 — Decode bounds each dimension but not the pixel count

**Severity:** Medium · **Confidence:** Confirmed-from-source that the bound is
absent; Needs testing that it terminates the process · **Effort:** M ·
**Category:** Input parsing

### The code today

`makeTexture` is the only size gate in the decode path, and it caps each *edge*
independently:

```swift
// Sources/FilmEngine/ImageDecoder.swift:116-119
func makeTexture(width: Int, height: Int) throws -> any MTLTexture {
    guard width > 0, height > 0, width <= 16_384, height <= 16_384 else {
        throw FilmError.invalid("Photo exceeds the supported texture dimensions")
    }
```

16384 × 16384 is **268 megapixels** and passes. Downstream of that gate, one decode
allocates three full-frame buffers:

```swift
// Sources/FilmEngine/ImageDecoder.swift:81-82
let texture = try makeTexture(width: width, height: height)      // w·h·8 bytes
var pixels = [Float](repeating: 0, count: width * height * 4)    // w·h·16 bytes
// Sources/FilmEngine/ImageDecoder.swift:108
let half = pixels.map(Float16.init)                              // w·h·8 bytes
```

At the cap that is 2 GiB + 4 GiB + 2 GiB ≈ **8 GiB transient**, before ImageIO's own
raster is counted.

Crucially, `maximumDimension` does **not** bound the peak. The full-resolution
`CGImage` is created first and only then drawn down:

```swift
// Sources/FilmEngine/ImageDecoder.swift:60
guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil), …
// Sources/FilmEngine/ImageDecoder.swift:102
context.draw(image, in: CGRect(x: 0, y: 0, width: drawWidth, height: drawHeight))
```

`context.draw` forces ImageIO to materialise the source raster at native size. So
the Preview's `maximumDimension: 2048` (`FilmApp/EditorModel.swift:29,158`) shrinks
the *output* buffers but not ImageIO's input buffer.

The Export path has no cap at all: `Renderer.texture(for:)` calls
`decoder.decode(data)` with `maximumDimension` defaulted to `nil`
(`Sources/FilmEngine/Renderer.swift:118`), fed the original bytes from
`FilmApp/EditorModel.swift:327`. `ImageWriter` then allocates the assembled frame on
top (`Sources/FilmEngine/Export/ImageWriter.swift:35`), and `TilePlan` budgets a
further `320 << 20` bytes of Tile textures (`Export/ExportTypes.swift:88`).

There is **no integer overflow** here — `16_384 * 16_384 * 4` is 2³⁰, far inside
`Int64` — so this is memory exhaustion, not corruption.

### Exploitation scenario

An attacker sends the user a PNG declaring 16384 × 16384 of a single flat colour.
Deflate compresses that to a few hundred kilobytes; it looks like a harmless small
file in Messages. The user saves it and opens it in Dye. On **open**, ImageIO
decompresses ~1 GiB of raster inside `context.draw`. If the app survives that, the
user taps Export and the decode runs again unbounded, this time keeping all three
full-frame buffers alive simultaneously.

### Impact

Denial of service: the app is killed by jetsam (`SIGKILL`, no crash report, no user
explanation) and any unsaved edit is lost. Repeatable at will, but the attacker
gains nothing else — no code execution, no data disclosure. On a local editor with
no persistent state worth destroying, this is a nuisance rather than a breach, which
is why it is Medium and not High. Note also that even a *legitimate* 48 MP frame
puts roughly 1.5 GiB through this path, which is likely the memory pressure the
README already flags as unvalidated ("a simulator does not reproduce the memory
pressure tiling exists for").

### Recommended fix

1. Add a total-pixel bound alongside the per-edge bound in `makeTexture`, e.g.
   `width * height <= 120_000_000` (comfortably above any consumer camera), with its
   own error message so the user is told the photo is too large rather than being
   killed.
2. Bound the *source* before decoding, not just the destination. Read
   `kCGImagePropertyPixelWidth`/`Height` from
   `CGImageSourceCopyPropertiesAtIndex` — which parses the header without decoding a
   pixel, the same trick already used in `FilmApp/EditorModel.swift:403-409` — and
   reject oversized frames there.
3. For the Preview path, replace `CGImageSourceCreateImageAtIndex` +
   `context.draw` with `CGImageSourceCreateThumbnailAtIndex` and
   `kCGImageSourceThumbnailMaxPixelSize: maximumDimension`, which lets ImageIO
   subsample during decode instead of materialising the full raster.
4. Avoid the second full-frame array at `ImageDecoder.swift:108` by converting
   `Float` → `Float16` in place or row-by-row into the texture.

### Acceptance criteria

- A synthetic 16384 × 16384 PNG is rejected with a `FilmError.invalid` naming the
  size limit, from both `Renderer.decode` and `Renderer.export`, without the process
  peak RSS exceeding ~200 MB.
- The Preview decode of a 48 MP JPEG has a peak RSS bounded by the 2048-pixel
  Preview, not by the source dimensions.
- A legitimate 48 MP Export still succeeds end to end and remains bit-identical to
  its untiled render (the existing
  `aTiledExportReproducesTheUntiledRenderOfTheSameFrame` assertion still passes).

### How to verify on a Mac

```sh
python3 - <<'PY'
from PIL import Image
Image.new("RGB", (16384, 16384), (128, 128, 128)).save("/tmp/bomb.png", optimize=True)
PY
ls -l /tmp/bomb.png   # expect a few hundred kB
```

Then add a test that calls `Renderer.decode(Data(contentsOf: bombURL))` and expects
a throw, and measure the real peak with:

```sh
xcrun xctrace record --template 'Allocations' \
  --launch -- .build/debug/FilmEnginePackageTests.xctest
```

On device, run the Export of a 48 MP frame under **Instruments → Allocations +
VM Tracker** and confirm the peak footprint stays under the jetsam limit for the
oldest supported device.

---

<a id="sec-02"></a>
## SEC-02 — No finiteness invariant between decode and `ImageWriter`

**Severity:** Low · **Confidence:** Confirmed-from-source that the trap is
unguarded; Needs testing whether a real photo reaches it · **Effort:** S ·
**Category:** Input parsing

### The code today

`LinearImage` has two initialisers. The public one enforces finiteness; the internal
one used by the renderer's own readback deliberately does not:

```swift
// Sources/FilmEngine/RenderTypes.swift:17-25
public init(width: Int, height: Int, rgba: [Float16]) throws {
    guard …, rgba.allSatisfy({ $0.isFinite }) else {
        throw FilmError.invalid("Invalid image dimensions or non-finite pixels")
    }
// Sources/FilmEngine/RenderTypes.swift:27-32
/// Renderer output: dimensions come from a texture and values are already float16.
init(unchecked width: Int, _ height: Int, _ rgba: [Float16]) {
```

`Renderer.readback` uses the unchecked one (`Sources/FilmEngine/Renderer.swift:942`),
and `ImageDecoder` never checks finiteness at all —
`Sources/FilmEngine/ImageDecoder.swift:108` runs `pixels.map(Float16.init)`, and
`Float16(_: Float)` rounds an out-of-range magnitude to **infinity** rather than
trapping. So there is no point in the pipeline that establishes "pixels are finite".

The writer then converts without a NaN guard:

```swift
// Sources/FilmEngine/Export/ImageWriter.swift:54-61
let alpha = min(max(Double(rgba[source + column * 4 + 3]), 0), 1)
for channel in 0..<4 {
    let value = Double(rgba[source + column * 4 + channel]) * (channel == 3 ? 1 : alpha)
    let quantised = (min(max(value, 0), 1) * maximum).rounded()
    let index = destination + column * 4 + channel
    if eightBit {
        raw.storeBytes(of: UInt8(quantised), toByteOffset: index, as: UInt8.self)
```

Swift's `min`/`max` are **not** NaN-clamping: `max(Double.nan, 0)` returns `nan` and
`min(nan, 1)` returns `nan`. `UInt8(Double.nan)` is a hard trap
(`"Double value cannot be converted to UInt8 because it is either infinite or NaN"`),
not a throwable error, so it cannot be caught by the `do/catch` in
`FilmApp/EditorModel.swift:321-353`. Infinity is handled correctly (it clamps to 1);
only NaN traps.

The pipeline can manufacture NaN from an infinity. The Output Transform's matrices
have mixed-sign coefficients, so an all-infinite pixel produces `-inf + inf`:

```metal
// Sources/FilmEngine/Metal/Pipeline.metal:632-639 (outputTransform)
float3x3 primaries = encoding == 1
    ? float3x3(float3(1.3435783f, -0.0652975f,  0.0028218f),
               float3(-0.2821797f, 1.0757879f, -0.0195985f),
               float3(-0.0613986f, -0.0104904f, 1.0167767f))
```

The same shape appears in `whiteBalance` (`Pipeline.metal:28`) and in `scanOutput`,
where `linear / (1.0f + linear)` is `inf/inf = NaN` for an infinite input
(`Pipeline.metal:472-473`).

### Exploitation scenario

A photo whose colour-managed conversion into the extended-linear Rec.2020 Working
Space produces a component above float16 range (65504) — a wide-gamut or HDR file,
or an image whose premultiplied alpha division at
`Sources/FilmEngine/ImageDecoder.swift:105-107` amplifies a channel — becomes `+inf`
in the texture, becomes `NaN` in the Output Transform, and traps the process the
moment the user taps Export.

I could **not** demonstrate a concrete file that does this; the plausible routes all
require an unusual source profile. What is confirmed is that there is no guard
anywhere on the path, and that the failure mode if it is ever reached is a trap
rather than an error.

### Impact

Process termination on Export. Same class as SEC-01: availability only. It is worth
fixing well below its severity because the fix is three characters of arithmetic and
the current code has no defence in depth at all.

### Recommended fix

Make the clamp NaN-safe in `ImageWriter.write`, which is the last line of defence
and costs nothing:

```swift
let clamped = value.isFinite ? min(max(value, 0), 1) : (value > 0 ? 1 : 0)  // NaN → 0
let quantised = (clamped * maximum).rounded()
```

Optionally, also flush non-finite values to a defined value in `outputTransform`
(`Pipeline.metal:640`), so an Exported LUT and a Preview agree with the file.

### Acceptance criteria

- `ImageWriter.write` fed a tile containing `Float16.nan` and `±Float16.infinity` in
  every channel including alpha produces a file rather than trapping, with NaN
  quantised to 0 and `+inf` to the format maximum.
- No behavioural change for any finite input: the existing
  `writersProduceTaggedFilesInEveryFormat` and
  `sRGBAndDisplayP3DifferOnlyInPrimaries` tests
  (`Tests/FilmEngineTests/ExportTests.swift:281,307`) still pass byte-for-byte.

### How to verify on a Mac

Unit test, no device needed beyond a Metal one:

```swift
@Test func nonFinitePixelsDoNotTrapTheWriter() throws {
    let writer = try ImageWriter(format: .tiff, output: .displayP3, width: 2, height: 1)
    let bad: [Float16] = [.nan, .infinity, -.infinity, .nan,  1, 1, 1, 1]
    bad.withUnsafeBufferPointer { writer.write($0, x: 0, y: 0, width: 2, height: 1) }
    _ = try writer.encode(quality: 1)
}
```

To settle the *reachability* question, fuzz the decoder against a corpus and assert
finiteness at the seam:

```sh
swift build -c debug -Xswiftc -sanitize=address
# then, over a corpus of mutated JPEG/PNG/HEIC:
#   let img = try renderer.decode(bytes)
#   #expect(img.rgba.allSatisfy(\.isFinite))
```

A corpus of a few thousand `radamsa`-mutated files derived from
`Tests/FilmEngineTests/Fixtures/` is enough to answer it.

---

<a id="sec-03"></a>
## SEC-03 — Every successful Export leaves a full-resolution copy of the photo in the temporary directory forever

**Severity:** Medium · **Confidence:** Confirmed-from-source · **Effort:** S ·
**Category:** Privacy

### The code today

Each Export writes the encoded frame to a fresh UUID-named directory under the app's
temporary directory:

```swift
// FilmApp/EditorModel.swift:416-432
nonisolated private static func write(_ data: Data, named name: String) async throws -> URL {
    try Task.checkCancellation()
    let url = try await Task.detached(priority: .utility) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }.value
    if Task.isCancelled {
        try? await Task.detached(priority: .utility) {
            try FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }.value
        throw CancellationError()
    }
    return url
}
```

The file is deleted in exactly two situations: the Export was **cancelled**
(`FilmApp/EditorModel.swift:425-430`), or saving to Photos **failed**
(`FilmApp/EditorModel.swift:340-343`). On the success path the URL is handed to the
`ExportRecord` so `ShareLink` can offer it (`FilmApp/ExportSheet.swift:229`) and is
then **never removed**. There is no cleanup on launch, on sheet dismissal
(`dismissExport()`, `FilmApp/EditorModel.swift:387-390`, only clears the enum), or on
backgrounding. The same applies to every `.cube` Exported LUT
(`FilmApp/EditorModel.swift:369`).

### Failure scenario

A user edits and exports twenty private photographs. Twenty UUID directories, each
holding a full-resolution HEIF/JPEG/TIFF render of a private photograph, accumulate
in `<container>/tmp/`. A 48 MP 16-bit TIFF is roughly 290 MB, so this is also a
silent storage leak. iOS purges `tmp/` opportunistically — under disk pressure and
occasionally between launches — but the timing is undocumented and unreliable, and
nothing purges it while the app is in the foreground.

### Impact

A copy of the user's photograph, at full resolution and after the user's edit, lives
in the app container indefinitely without the user's knowledge and with no UI that
lists or deletes it. Mitigating factors are real and worth stating: `tmp/` is
excluded from iTunes/iCloud backup, it is inside the app's sandbox and unreachable by
other apps, there is no `UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace`
in the project so it is not visible in the Files app (see
[Confirmed healthy](#confirmed-healthy)), and the file is protected at rest by
`NSFileProtectionCompleteUntilFirstUserAuthentication` (the iOS default) so it is
unreadable while the device is locked before first unlock. The exposure is therefore
to someone with an unlocked device and a forensic tool, not to a remote attacker —
but "we keep an undeleted copy of every photo you export" is still the wrong default
for an app whose entire pitch is local-only photo editing.

### Recommended fix

1. Delete the Export directory once it is no longer reachable — when
   `dismissExport()` runs, when a new Export starts, and when
   `EditorModel` is torn down. The `ExportRecord` already owns the URL
   (`FilmApp/EditorModel.swift:251-263`), so the lifetime is well defined.
2. Sweep any leftover directories at launch: enumerate
   `FileManager.default.temporaryDirectory` and remove entries whose name parses as a
   `UUID`. This is cheap and repairs installs that already leaked.
3. Consider setting `.completeFileProtection` explicitly on the written file
   (`data.write(to: url, options: [.atomic, .completeFileProtection])`) so it is
   unreadable whenever the device is locked, not merely before first unlock. Note
   this must be reverted or handled if a background export is ever added.

### Acceptance criteria

- After an Export completes and the export sheet is dismissed, the exported file and
  its parent directory no longer exist. Assert with
  `FileManager.default.fileExists(atPath:)`.
- `ShareLink` still works for the whole time the finished-export sheet is on screen
  (the file must outlive the share, so deletion is on dismissal, not on save).
- On launch, a temporary directory pre-seeded with three UUID-named directories is
  empty afterwards, and any non-UUID entry is left alone.
- Cancelling an Export still removes the partial directory (existing behaviour, do
  not regress).

### How to verify on a Mac

Instrument the container directly on a simulator run:

```sh
xcrun simctl get_app_container booted app.memoji.dye data
# export a photo in the app, then:
find "$(xcrun simctl get_app_container booted app.memoji.dye data)/tmp" -type f -ls
```

Expect the file to be present while the finished sheet is up and gone after
dismissal. On a device, use **Xcode → Window → Devices and Simulators → Download
Container** and inspect `AppData/tmp/` after several exports.

---

<a id="sec-04"></a>
## SEC-04 — RAW extent is converted to `Int` without a finiteness or range check

**Severity:** Low · **Confidence:** Likely · **Effort:** S · **Category:** Input parsing

### The code today

```swift
// Sources/FilmEngine/ImageDecoder.swift:49-50
guard let image = raw.outputImage, !image.extent.isEmpty, !image.extent.isInfinite else {
    throw FilmError.invalid("RAW decode failed")
}
let texture = try makeTexture(width: Int(image.extent.width), height: Int(image.extent.height))
```

The two guards do not cover the two cases that trap:

- **NaN.** `CGRect.isEmpty` is `width <= 0 || height <= 0`; every comparison against
  NaN is false, so a NaN-width rect is neither empty nor infinite. `Int(Double.nan)`
  traps.
- **Large but finite.** `CGRect.isInfinite` is true only for the infinite rect
  sentinel, not for a rect whose width is, say, `1e300`. `Int(1e300)` traps with
  *"Double value cannot be converted to Int because it is outside the representable
  range"*.

Both are traps, so the `try` and the surrounding `catch`
(`FilmApp/EditorModel.swift:150-185`) cannot intercept them. Note the same pattern is
handled correctly in the non-RAW branch, where the dimensions come from
`image.width`/`image.height`, which are already `Int`
(`Sources/FilmEngine/ImageDecoder.swift:74-80`).

### Exploitation scenario

A malformed DNG whose IFD declares degenerate dimensions is handed to
`CIRAWFilter(imageData:identifierHint:)` (`ImageDecoder.swift:29`). If Core Image
propagates that into `outputImage.extent` rather than returning `nil`, the `Int(_:)`
conversion terminates the process. I could not test whether Core Image sanitises
this; treat it as an unverified but cheap-to-close hole.

### Impact

Process termination on opening a crafted RAW file. Availability only.

### Recommended fix

```swift
let extent = image.extent
guard extent.width.isFinite, extent.height.isFinite,
      extent.width >= 1, extent.height >= 1,
      extent.width <= 16_384, extent.height <= 16_384 else {
    throw FilmError.invalid("RAW decode failed")
}
let texture = try makeTexture(width: Int(extent.width), height: Int(extent.height))
```

Apply the same shape to `raw.nativeSize` at `ImageDecoder.swift:33-36`, where a NaN
`native` would silently skip the scale-factor branch rather than trap, but a
non-finite `nativeSize` is still a signal the file should be rejected.

### Acceptance criteria

- A DNG fixture that yields a non-finite or out-of-range extent throws
  `FilmError.invalid` rather than trapping.
- `rawDecodePreservesSceneLinearExposureRatios`
  (`Tests/FilmEngineTests/RendererTests.swift:63`) still passes against
  `linear-low.dng` / `linear-high.dng`.

### How to verify on a Mac

Extend `Scripts/make-raw-fixtures.py` to emit hostile variants — zero `ImageWidth`,
`ImageWidth = 0xFFFFFFFF`, mismatched strip offsets — and assert the decoder throws.
Then fuzz the RAW branch specifically:

```sh
radamsa -n 2000 Tests/FilmEngineTests/Fixtures/linear-low.dng -o /tmp/raw-%n.dng
# feed each through Renderer.decode under a debug build and expect throw-or-succeed,
# never a trap; run under `lldb -o run -o bt` to catch the fatal error site.
```

---

<a id="sec-05"></a>
## SEC-05 — No privacy manifest, and the app target's Resources build phase is empty

**Severity:** Low · **Confidence:** Confirmed-from-source · **Effort:** S ·
**Category:** Privacy

### The code today

The app generates its `Info.plist` and declares exactly one usage description:

```
FilmApp.xcodeproj/project.pbxproj:243-246
GENERATE_INFOPLIST_FILE = YES;
INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = "Dye saves your exported photos to your photo library.";
INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
INFOPLIST_KEY_UILaunchScreen_Generation = YES;
```

That is *correct and minimal* — see [Confirmed healthy](#confirmed-healthy) — but
there is no `PrivacyInfo.xcprivacy` anywhere in the repository, and the app target's
Resources build phase contains no files at all:

```
FilmApp.xcodeproj/project.pbxproj:192-200
/* Begin PBXResourcesBuildPhase section */
    0189424A5A60FED329FA868E /* Resources */ = {
        isa = PBXResourcesBuildPhase;
        buildActionMask = 2147483647;
        files = (
        );
```

So even if a manifest were added to disk it would not be bundled without also being
added to that phase.

### Impact

This is primarily a submission-blocking issue, which a separate audit owns. It is
listed here because of the *privacy-correctness* half: a manifest is the only
machine-readable place where "this app collects no data and links no tracking
domains" is stated, and Dye's claim there is unusually strong and worth recording.

On required-reason APIs, I grepped the shipping code for every category and found
**none in use**: no `UserDefaults`, no file-timestamp APIs (`attributesOfItem`,
`contentModificationDate` on a file), no `systemUptime`/`mach_absolute_time`, no disk
space APIs, no active-keyboard APIs. (`creationDate` appears at
`FilmApp/EditorModel.swift:302,337` and
`Sources/FilmEngine/Export/ImageWriter.swift:85`, but those are an *EXIF* date and a
`PHAssetCreationRequest` property, not the file-timestamp API category.) The manifest
can therefore declare an empty `NSPrivacyAccessedAPITypes` array, which is the
cleanest possible position.

### Recommended fix

Add `FilmApp/PrivacyInfo.xcprivacy`, add it to the Resources build phase, and
populate it with:

- `NSPrivacyTracking`: `false`
- `NSPrivacyTrackingDomains`: `[]`
- `NSPrivacyCollectedDataTypes`: `[]`
- `NSPrivacyAccessedAPITypes`: `[]`

Cross-reference: the App Store submission audit owns the *approval* side of this;
this entry owns only the accuracy of the four values above, which the privacy
data-flow map below substantiates.

### Acceptance criteria

- `PrivacyInfo.xcprivacy` exists, is listed in the `PBXResourcesBuildPhase` `files`
  array, and appears at the root of the built `.app`.
- The four keys above hold the stated values, and a re-audit of the data-flow map
  after any new API call keeps them true.

### How to verify on a Mac

```sh
xcodebuild -project FilmApp.xcodeproj -scheme FilmApp -sdk iphonesimulator \
  -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO build
find .build/app -name 'PrivacyInfo.xcprivacy' -path '*Dye.app*'
plutil -p "$(find .build/app -name 'PrivacyInfo.xcprivacy' | head -1)"
```

Then generate Xcode's own report (**Product → Archive → Generate Privacy Report**)
and confirm it lists no collected data and no accessed API categories.

---

<a id="sec-06"></a>
## SEC-06 — CI actions are pinned to floating major tags

**Severity:** Low · **Confidence:** Confirmed-from-source · **Effort:** S ·
**Category:** Supply chain

### The code today

```yaml
# .github/workflows/ci.yml:22,43,75,91
- uses: actions/checkout@v7
- uses: actions/upload-artifact@v7
# .github/workflows/profile-candidates.yml:19,46
- uses: actions/checkout@v7
- uses: actions/upload-artifact@v7
```

A major-version tag is mutable. If the upstream repository were compromised, or a
maintainer moved `v7`, arbitrary code would execute on the runner on the next CI run
without any change to this repository.

### Impact

Deliberately low, because the blast radius here is unusually small and that is worth
recording rather than glossing:

- Both workflows declare `permissions: contents: read` at the top level
  (`ci.yml:12-13`, `profile-candidates.yml:7-8`), so the `GITHUB_TOKEN` cannot write.
- Neither workflow references `secrets.*` at all. There is nothing to exfiltrate.
- Neither uses `pull_request_target`; both use plain `pull_request`, so fork PRs run
  without secrets by GitHub's own rules.
- Untrusted PR data is handled correctly: `github.event.pull_request.base.sha` is
  passed through the `env:` block and referenced as `"$BASE_SHA"`
  (`ci.yml:29-36`), never interpolated into a `run:` string.

The realistic damage is a poisoned build artifact (`step-wedges`,
`film-profile-candidates`) or a tampered Catalogue bake that a reviewer might trust.

### Recommended fix

Pin every action to a full commit SHA with the tag in a trailing comment, e.g.
`uses: actions/checkout@<40-hex-sha> # v7.0.0`, and adopt Dependabot for the
`github-actions` ecosystem so the pins are maintained rather than frozen.

Separately, **preserve the two properties that make this Low**: never convert either
workflow to `pull_request_target`, and never add a repository secret to a workflow
that runs fork-authored code (`swift build`, `swift test` and
`Scripts/bake-catalogue.sh` all execute code from the PR branch). If a secret is ever
needed, split the privileged step into a separate `workflow_run` job.

### Acceptance criteria

- Every `uses:` in `.github/workflows/` names a 40-character commit SHA.
- `grep -rn 'pull_request_target\|secrets\.' .github/workflows/` returns nothing.
- CI still passes on a no-op PR.

### How to verify on a Mac

```sh
grep -rn 'uses:' .github/workflows/ | grep -v '@[0-9a-f]\{40\}'   # expect no output
gh api repos/actions/checkout/git/ref/tags/v7 --jq .object.sha    # resolve the pin
```

---

<a id="sec-07"></a>
## SEC-07 — Profile `id` becomes a filename component with no path sanitisation

**Severity:** Informational · **Confidence:** Confirmed-from-source · **Effort:** S ·
**Category:** Platform hardening

### The code today

```swift
// FilmApp/EditorModel.swift:330
let url = try await Self.write(data, named: "\(profile.id).\(format.fileExtension)")
// FilmApp/EditorModel.swift:369
let url = try await Self.write(data, named: "\(profile.id).cube")
```

`name` is then passed to `directory.appendingPathComponent(name)`
(`FilmApp/EditorModel.swift:421`), which happily accepts `../` segments.
`FilmProfile.validate()` only requires the id to be non-empty:

```swift
// Sources/FilmEngine/Profiles/FilmProfile.swift:316
try require(!id.isEmpty && !displayName.isEmpty, "missing identity or Display Name")
```

**This is not exploitable today.** `ProfileContainer.decode` and
`ProfileContainer.load` are called from exactly three places — `ProfileCatalogue`
(`Sources/FilmEngine/Profiles/ProfileCatalogue.swift:8`), the Baker
(`ProfileBaker/ProfileBaker.swift:33,44`) and the test suite — and the app only ever
reaches them via `ProfileCatalogue.bundled()`
(`FilmApp/EditorModel.swift:141`), which reads
`Bundle.module.resourceURL/Catalogue`. Every id is therefore from the signed app
bundle and matches `[a-z0-9-]+`.

### Why it is worth recording

The moment a Profile can be imported — a share sheet, a Files picker, an iCloud
Catalogue, a community stock pack — a Profile carrying
`id: "../../Library/Preferences/com.apple.something"` writes an attacker-named file
outside the intended directory. The cost of closing it now is one guard.

### Recommended fix

Tighten the id in `FilmProfile.validate()`, which is the right home because the
constraint belongs to the Profile rather than to the exporter:

```swift
try require(!id.isEmpty && id.count <= 64 &&
            id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") },
            "Profile id must be a short ASCII slug")
```

and, belt and braces, sanitise at the call site in `EditorModel.write` by rejecting
any `name` containing `/` or `..`.

### Acceptance criteria

- A `FilmProfile` with an id containing `/`, `..`, a NUL, or a non-ASCII character
  fails `validate()` and therefore fails `ProfileContainer.decode`.
- Every shipped `.filmprofile` in `Sources/FilmEngine/Catalogue/` still loads, and
  `ProfileCatalogue.bundled()` still returns all seventeen Profiles.

### How to verify on a Mac

Add a case to `malformedContainersAndIncompleteProvenanceFail`
(`Tests/FilmEngineTests/ProfileCodecTests.swift:34`) that re-encodes a valid Profile
with a traversal id and expects a throw, then run
`swift test --filter ProfileCodec`.

---

<a id="sec-08"></a>
## SEC-08 — Metal shader source ships as a bundle text resource and is compiled at runtime

**Severity:** Informational · **Confidence:** Confirmed-from-source · **Effort:** M ·
**Category:** Platform hardening

### The code today

```swift
// Sources/FilmEngine/Renderer.swift:44-48
let url = Bundle.module.url(forResource: "Pipeline", withExtension: "metal", subdirectory: "Metal")!
let options = MTLCompileOptions()
if #available(macOS 15, iOS 18, *) { options.mathMode = .safe }
else { options.fastMathEnabled = false }
let library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: options)
```

`Package.swift:10` copies the whole `Metal` directory as a resource, so
`Pipeline.metal` is plaintext inside the app bundle and is compiled from source on
every cold launch. The canvas does the same with an inline string
(`FilmApp/FilmCanvas.swift:61-83`).

### Assessment

This is **not** a code-injection vector: the bundle is code-signed and sealed, so the
`.metal` file cannot be modified on a non-jailbroken device without invalidating the
signature. `options.mathMode = .safe` is a good choice and is what keeps the Golden
Image guarantees honest.

Two things it does cost, both worth stating rather than filing as vulnerabilities:

- **First-launch latency.** `Renderer.make()` already routes compilation to a
  detached task specifically because of this
  (`Sources/FilmEngine/Renderer.swift:60-64`), which is a workaround for a cost a
  precompiled `.metallib` would not have.
- **Source disclosure.** The pipeline source is readable by anyone who unzips the
  IPA. That is a business consideration, not a security one, and it is arguably a
  feature for a project this open about its model.

The one hard force-unwrap here — `Bundle.module.url(...)!` at
`Renderer.swift:44` — is trusted-by-construction (a resource declared in
`Package.swift`), as is `try!` at
`Sources/FilmEngine/Profiles/Profile.swift:63` for `identity.json`. Both fail loudly
at launch if the bundle is corrupt, which is the correct behaviour for a sealed
resource.

### Recommended fix (optional)

Build `Pipeline.metal` into a `.metallib` at build time (an SPM `.process` rule with
a Metal build tool plugin, or an Xcode build phase invoking `xcrun metal` +
`metallib`) and load it with `device.makeDefaultLibrary(bundle:)`. Keep
`-fno-fast-math` in the compile flags so numerical results are unchanged.

### Acceptance criteria

- `Renderer.init` loads a precompiled library and does not read `.metal` source.
- All seventeen Golden Images
  (`Tests/FilmEngineTests/Fixtures/GoldenImages/`) still match bit-for-bit under
  `catalogueRendersMatchGoldenImages`. This is the load-bearing check: if the
  compiler flags differ, the goldens will say so.

### How to verify on a Mac

```sh
swift test --filter catalogueRendersMatchGoldenImages
unzip -l .build/app/Build/Products/Debug-iphonesimulator/Dye.app | grep -i metal
```

---

## Privacy data-flow map

Every category of user data in the app, where it comes from, where it lands, and how
long it lives. **Nothing in this table leaves the device by any code path in this
repository** — there is no networking code at all (verified by grep for
`URLSession`, `WKWebView`, `NSURLConnection`, `dataTask`, `Network.`, sockets and
`http`/`https` literals across every shipping `.swift` file; the only match in the
whole tree is an SVG XML namespace in `ProfileBaker/StepWedge.swift:110`). Anything
that reaches another party does so through a user-initiated system UI (the share
sheet, or the Photos library).

| Data | Source | Written to | Lifetime | Leaves the device? |
|------|--------|-----------|----------|--------------------|
| **Photo pixels — original bytes** | `PhotosPickerItem.loadTransferable(type: Data.self)`, `FilmApp/EditorModel.swift:153` | In-memory only: `EditorModel.original` (`:172`) | Until another photo is opened or the app is killed. Never written to disk. | No |
| **Photo pixels — Preview** | `Renderer.decode(_:maximumDimension: 2048)`, `FilmApp/EditorModel.swift:158` | GPU textures + a `[Float16]` in `LinearImage`; drawn to a `CAMetalLayer` (`FilmApp/FilmCanvas.swift:92-95`) | Process lifetime | No |
| **Photo pixels — thumbnails** | `Renderer.decode(_:maximumDimension: 192)`, `FilmApp/EditorModel.swift:178` | In-memory dictionaries `thumbnails`, `presetThumbnails` (`:18,208`) | Process lifetime; cleared on new photo (`:168-169`) | No |
| **Photo pixels — Export file** | `Renderer.export(...)`, `FilmApp/EditorModel.swift:327` | `tmp/<UUID>/<profileID>.<ext>`, `FilmApp/EditorModel.swift:419-422` | **Indefinite — see [SEC-03](#sec-03).** Removed only on cancel or Photos-save failure | Only if the user taps Share (`FilmApp/ExportSheet.swift:229`) |
| **Photo pixels — Photos asset** | `PHAssetCreationRequest.addResource(with: .photo, fileURL:)`, `FilmApp/EditorModel.swift:336-338` | The user's photo library, add-only | Owned by the user | Only via the user's own iCloud Photos settings |
| **EXIF — read** | `ExportDate.originalDate(in:)` parses only `DateTimeOriginal`, `DateTimeDigitized`, `TIFF/DateTime` and their UTC offsets (`Sources/FilmEngine/Export/ExportDate.swift:328-355`); `ImageDecoder` reads only `kCGImagePropertyProfileName`, `ExifColorSpace` and `Orientation` (`ImageDecoder.swift:64-72`) | In-memory `originalDate` (`FilmApp/EditorModel.swift:173`) | Process lifetime | No |
| **EXIF/GPS — written to exports** | — | **Stripped.** `ImageWriter.encode` builds a fresh `CGImage` from raw pixels and attaches only the properties it constructs itself (`Sources/FilmEngine/Export/ImageWriter.swift:70-90`). The only metadata written is the date dictionary from `ExportDate.properties(for:)` (`ExportDate.swift:357-374`), plus a colour-space tag. **No GPS, no camera make/model, no serial number, no lens data, no original EXIF survives.** | n/a | No |
| **Export date** | User's `ExportDate` choice: `.today` (now) or `.original` (the source photo's EXIF date) (`FilmApp/EditorModel.swift:302`) | EXIF `DateTimeOriginal`/`DateTimeDigitized` in the exported file and `PHAsset.creationDate` | Life of the file | Only through the exported file, at the user's choice |
| **Presets** | User's name string + `RenderSettings` JSON, `FilmApp/PresetSheet.swift:11-16` | SwiftData store in the app container (`FilmApp/FilmApp.swift:7`, `.modelContainer(for: Preset.self)`) | Until the user swipes to delete (`FilmApp/PresetSheet.swift:115`) | No. Default `ModelConfiguration` is local; no CloudKit container is configured and no `com.apple.developer.icloud-*` entitlement exists |
| **Exported LUT (`.cube`)** | `Renderer.exportedLUT`, `FilmApp/EditorModel.swift:367` | `tmp/<UUID>/<profileID>.cube` (`:369`). Carries the Stock name and the user's control values in its `TITLE` line (`Sources/FilmEngine/Export/ExportedLUT.swift:55,71-86`) — a look, not a photograph | **Indefinite — see [SEC-03](#sec-03)** | Only if the user taps Share |
| **Logs** | — | **Nothing.** There is no `os_log`, `Logger`, `NSLog`, `print` or `debugPrint` anywhere in `FilmApp/` or `Sources/FilmEngine/`. The only `print` calls in the repository are in `ProfileBaker/` (a CLI that never ships) and in the test suite | n/a | No |
| **Analytics / telemetry / crash reporting** | — | **None.** `Package.swift` declares zero dependencies; no SDK is linked | n/a | No |
| **Error messages** | `error.localizedDescription`, e.g. `FilmApp/EditorModel.swift:342,352` | On-screen text only | Transient | No |

**Photo library permissions.** The README's claim is accurate. Reading uses
`PhotosPicker`/`PhotosPickerItem` (`FilmApp/EditorModel.swift:145-153`), which runs
out of process and requires **no** permission and no
`NSPhotoLibraryUsageDescription` — and indeed the project declares none. Writing
requests `PHPhotoLibrary.requestAuthorization(for: .addOnly)`
(`FilmApp/EditorModel.swift:322`), the narrowest available scope, backed by
`INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription`
(`FilmApp.xcodeproj/project.pbxproj:244`). The app can never enumerate the user's
library.

---

## Verification backlog

Dynamic tests that require a Mac with Xcode, a Metal device and (where noted) a real
iPhone. Ordered by value.

1. **Photo-decoder fuzzing.** Build the package with ASan and UBSan
   (`swift build -Xswiftc -sanitize=address -Xswiftc -sanitize=undefined`) and drive
   `Renderer.decode` over a few thousand `radamsa`-mutated JPEG/PNG/HEIC/DNG derived
   from `Tests/FilmEngineTests/Fixtures/`. Assert: throws or succeeds, never traps,
   never reports a sanitiser error. Settles SEC-02 and SEC-04 and is the single
   highest-value test in this list.
2. **Decompression bomb.** The 16384 × 16384 flat PNG from
   [SEC-01](#sec-01), through both `decode(maximumDimension: 2048)` and `export`,
   measured under Instruments → Allocations. Settles SEC-01.
3. **On-device Export memory ceiling.** A real 48 MP HEIC on the oldest supported
   iPhone, watched in VM Tracker with the jetsam limit in view. The README already
   flags this as outstanding; the security angle is that an attacker-chosen
   resolution sits on the same curve.
4. **Temporary-directory lifecycle.** Ten exports on a device, then download the app
   container and enumerate `tmp/`. Settles SEC-03 and confirms whatever cleanup is
   implemented.
5. **EXIF/GPS strip verification.** Export a geotagged photo and run
   `exiftool -a -G1 -s exported.heic` and `exiftool -gps:all exported.jpg`. Assert no
   GPS group, no `Make`/`Model`/`SerialNumber`/`LensInfo`, only the date fields and
   the ICC tag. This confirms the strongest privacy property in the map above.
6. **Metal API validation over the Export path.** Run the export tests with
   `MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1` and the scheme's *Metal API
   Validation* set to Extended. This is what would catch any `getBytes` region or
   `setBytes` length mismatch in the tiled path that static reading cannot rule out —
   in particular the `MTLRegionMake2D(tile.insetX, tile.insetY, …)` read at
   `Sources/FilmEngine/Export/Export.swift:83-84` against the padded Tile bounds.
7. **Non-finite pixel end-to-end.** Construct a `LinearImage` containing `±inf` and
   `NaN` via the unchecked path, render it, export it in all three formats. Settles
   the reachability half of SEC-02.
8. **Built `Info.plist` inspection.** `plutil -p` the `Info.plist` inside the built
   `.app` and confirm what the generated file actually contains: no
   `NSAppTransportSecurity`, no `CFBundleURLTypes`, no `UIBackgroundModes`, no
   `UIFileSharingEnabled`, no `LSSupportsOpeningDocumentsInPlace`, and exactly one
   usage-description key. Static reading of `project.pbxproj` says all of this, but
   only the built artefact proves it.
9. **Entitlements inspection.** `codesign -d --entitlements :- Dye.app` on a signed
   build. Expect only the automatic `application-identifier`,
   `com.apple.developer.team-identifier` and `get-task-allow` (Debug only) —
   no App Groups, no keychain access group, no iCloud.
10. **Preset store location.** Confirm the SwiftData store lands in
    `Library/Application Support/` inside the container and that no CloudKit
    container is created, closing out the "Presets never leave the device" row.

---

## Confirmed healthy

Checked, found sound, and recorded here so nobody spends the effort again.

**Networking, telemetry, third-party code**
- No networking API of any kind in shipping code. No analytics, no crash reporter, no
  advertising or attribution SDK.
- `Package.swift:1-15` declares **zero external dependencies**. The entire supply
  chain is Apple's SDK plus this repository.
- No `os_log`/`Logger`/`NSLog`/`print` in `FilmApp/` or `Sources/FilmEngine/`, so no
  user content, file path or photo metadata can reach the device log.
- No Keychain use, no `SecItem`, no credential storage — because there is nothing to
  store.

**Profile and Preset deserialisation** (the declared Test Seam)
- `ProfileContainer.decode`/`load` are reachable only from
  `ProfileCatalogue.bundled()`, the Baker CLI and tests. **No share sheet, Files
  importer, `onOpenURL`, `NSItemProvider`, drag-and-drop or pasteboard path can
  deliver a Profile.** Bundled Profiles are therefore trusted-by-construction, and
  the codec is not an untrusted parser today.
- Despite that, the codec is properly hardened, which is the right posture in case an
  import path is ever added. `ProfileContainer.headerLength`
  (`Sources/FilmEngine/Profiles/ProfileContainer.swift:73-80`) checks magic, version
  and a `0 < length <= 4 MiB` header bound; `decode` bounds the whole file at 128 MiB
  and checks `bytes.count >= 16 + count` before slicing (`:47-51`).
- `ProfileContainer.validate` (`:82-105`) forces payload offsets to be **contiguous
  from zero** (`entry.offset == end`), forces every length to equal an
  independently computed expected size, forbids duplicate and unexpected names, and
  requires `end == payloadLength` so trailing bytes are rejected. Offsets are
  structurally non-negative; every `subdata(in:)` range at `:55` is bounded by that
  check.
- The `size * size * size * 8` arithmetic at `ProfileContainer.swift:87,91` cannot
  overflow, because `FilmProfile.validate()` bounds `colour.lutSize` to `2...129`
  (`Sources/FilmEngine/Profiles/FilmProfile.swift:318`) and `densityOutput.lutSize`
  to `2...65` (`:426`) *before* it runs (`:83`). Max value is 129³·8 ≈ 17 MB.
- `decodeHalfValues` (`ProfileContainer.swift:135-169`) rejects odd-length payloads,
  copies once into an exactly-sized buffer, and validates the IEEE-754 exponent bits
  four lanes at a time with a correct tail loop — so **no non-finite value can ever
  enter a Colour Cube or a Density Curve**. The bit trick is genuinely correct: the
  masked 5-bit exponents cannot carry into one another.
- Every force-unwrap and every fixed-index array access in `Renderer.plan` and its
  helpers is covered by a `FilmProfile.validate()` precondition. I traced each one:
  `halation.radiusMicrons[0..2]` and `halation.tint[0..2]`
  (`Renderer.swift:760,776`) ← `nonnegative(..., count: 3)` at `FilmProfile.swift:384-385`;
  `grain.channelRadiusScale[channel]` (`Renderer.swift:557`) ← count 3 at `:372`;
  `curve.first!`/`curve.last!` (`Renderer.swift:581`) ← `measured.count == 3` and
  `curve.count >= 2` with strictly increasing density at `:375-377`;
  `channelPoints[0]` (`Renderer.swift:620`) ← `channels.count == 3` at `:395`;
  `lowerVariant!` and `outputs.first { … }!` (`Renderer.swift:476`) ← `matches(...)`
  at `:431` plus the non-empty `lutVariants` requirement at `:320`;
  `printVariants!` (`Renderer.swift:426,475`) ← guarded at `Renderer.swift:421` and
  `FilmProfile.swift:432`; `radiusMicrons.max()!` (`Renderer.swift:750`) ← count 3.
  The blend divisor at `Renderer.swift:439` cannot be zero because `pushStops` are
  required unique and finite at `FilmProfile.swift:322-323`.
- `RenderSettings.validate()` (`Sources/FilmEngine/RenderTypes.swift:163-190`)
  range-checks and finiteness-checks **every** numeric control, and
  `Adjustments.validate()` does the same for all eight Adjustments. It is called at
  the top of `render` (`Renderer.swift:79`), `tilePlan` (`Export.swift:54`) and
  `exportedLUT` (`ExportedLUT.swift:29`), and before applying a Preset
  (`FilmApp/EditorModel.swift:442`). A hand-edited Preset row cannot reach the shader
  with an out-of-range value.
- Presets are local SwiftData rows holding a JSON `RenderSettings` blob
  (`FilmApp/PresetSheet.swift:5-16`). They are decoded with `try?` and validated
  before use; they are never shared, exported or imported.

**GPU memory safety** (`Sources/FilmEngine/Metal/Pipeline.metal`, read in full)
- **Every** kernel begins with a grid-bounds guard
  (`if (p.x >= output.get_width() || p.y >= output.get_height()) return;`) — verified
  on all 22 kernels named in `Renderer.swift:50-53`.
- Every neighbour-reading texture access is clamped to the texture's own extent:
  `scatterDownsample:88-91`, `scatterBlur:102-107`, `mtfBlur:194-201`. The two
  sampler-based reads (`scatterUpsample:151`, `geometry:600`) use
  `address::clamp_to_edge`.
- `tetrahedral` (`Pipeline.metal:226-242`) clamps the base coordinate to
  `cube.get_width() - 2` so `v0 + 1` is always in range, for a cube whose size the
  codec has already bounded to `2...129`.
- The two `constant float *` buffers are exactly sized against their shader-side
  indexing. `densityResponse` is indexed at most `2*32 + 30 + 1 = 95`
  (`Pipeline.metal:420,448`) against a 96-element buffer, guaranteed by
  `nonnegative(grain.densityResponse, count: 32)` (`FilmProfile.swift:372`) and the
  three-channel construction at `Renderer.swift:575,588-595`. `coefficients` is
  indexed `0..<3` (`Pipeline.metal:219-221`) against a buffer the renderer refuses to
  build unless `coefficients.count == 3` (`Renderer.swift:655`).
- The `bandCount`/`contributions` pair (`Pipeline.metal:302-311`) is safe in both
  directions: `bandCount` is set from `contributions.count`
  (`Renderer.swift:221-225`), the empty case binds a dummy element with
  `bandCount == 0` so the loop never runs, and `FilmProfile.validate()` bounds the
  count to `31...81` (`:358`) — 1296 bytes, comfortably inside Metal's 4 KB
  `setBytes` limit.
- `Renderer.readback` (`:935-943`) sizes its `unsafeUninitializedCapacity` buffer as
  `width * height * 4` `Float16` and reads with `bytesPerRow: width * 8` over the
  full region — exactly consistent.
- `ImageWriter.write` bounds itself with two `precondition`s
  (`Sources/FilmEngine/Export/ImageWriter.swift:43-44`) and its byte offsets are
  correct for both the 8-bit (`index`) and 16-bit (`index * 2`) cases against a
  buffer of `width * height * 4 * bytesPerComponent`.
- `MTLCompileOptions.mathMode = .safe` / `fastMathEnabled = false`
  (`Renderer.swift:46-47`) — no fast-math reassociation, which is what makes the
  Golden Images meaningful.

**Platform hardening** (from `FilmApp.xcodeproj/project.pbxproj`, both configurations)
- **No entitlements file.** No `CODE_SIGN_ENTITLEMENTS` in either build
  configuration, so no App Groups, no keychain sharing, no iCloud/CloudKit, no
  associated domains, no network client entitlement on macOS.
- **No ATS override.** No `NSAppTransportSecurity` key, so the default (strict)
  policy applies — moot given there is no networking, but correctly left alone.
- **No `UIFileSharingEnabled`, no `LSSupportsOpeningDocumentsInPlace`.** The app
  container, including the temporary directory discussed in SEC-03, is not browsable
  from the Files app.
- **No `CFBundleURLTypes` and no `onOpenURL`/`openURL` handler** anywhere in the
  source. No custom URL scheme, no Universal Link handler, so no external app can
  hand Dye an input.
- **No `UIBackgroundModes`.** All work is foreground.
- **No pasteboard use.** No `UIPasteboard` reference in the entire tree. The only
  outbound sharing is a user-driven `ShareLink`
  (`FilmApp/ExportSheet.swift:229`).
- **No `WKWebView`, no `JavaScriptCore`, no dynamic code loading** beyond the Metal
  shader compilation covered in SEC-08.
- `SWIFT_STRICT_CONCURRENCY = complete` and `SWIFT_VERSION = 6.0` in both
  configurations (`project.pbxproj:250-253`), with the package on
  `swiftLanguageModes: [.v6]` (`Package.swift:14`). The renderer is an `actor` owning
  its GPU state (`Renderer.swift:6`), which removes a whole class of data-race bugs
  at compile time.
- The one `@unchecked Sendable` in the app (`ThermalObserver`,
  `FilmApp/EditorModel.swift:582`) is justified in a comment and carries only an
  observer token and an `AsyncStream`; the notification payload never crosses an
  isolation boundary.
- `DEVELOPMENT_TEAM = X76BWPRADX` is committed (`project.pbxproj:242`). A Team ID is
  public information printed in every signed binary; this is not a secret leak.

**Input handling that is already right**
- **Untagged images are rejected rather than assumed sRGB**
  (`Sources/FilmEngine/ImageDecoder.swift:60-70`). ImageIO hands back a default sRGB
  space even for an untagged file, and the code correctly requires the *metadata* to
  establish the assignment. `untagged.png` and
  `untaggedInputDoesNotSilentlyAssumeSRGB`
  (`Tests/FilmEngineTests/RendererTests.swift:79`) guard it.
- EXIF orientation is applied through an explicit 1–8 switch with a `default: break`
  (`ImageDecoder.swift:91-100`); an out-of-range orientation value degrades to
  identity rather than indexing anything.
- `ExportDate.originalDate` requires a syntactically complete 19-character EXIF date
  and round-trips it through the formatter before accepting it
  (`Sources/FilmEngine/Export/ExportDate.swift:345-346`), so a malformed or
  all-zeroes date string cannot produce a nonsense `Date`.
- The RAW path explicitly disables every one of Core Image's photographic boosts
  before the scene-referred handoff (`ImageDecoder.swift:37-48`) and uses an explicit
  command buffer with `waitUntilCompleted` to avoid racing the decode
  (`:51-57`) — correct, and the comment says why.
- The premultiplied-alpha division at `ImageDecoder.swift:105-107` is guarded by
  `where pixels[i + 3] > 0`, so no divide-by-zero.

**Developer tooling** (Baker, `Scripts/`, CI — never ships in the app)
- No `eval`, no `exec`, no `os.system`, no `shell=True`, no `pickle`, no
  `yaml.load`, and no network fetch in any Python script. Every `subprocess` call
  uses the argv-list form (`Scripts/ci_scope.py:33-35`,
  `Scripts/check-dial-mapping.py:17,43,47`,
  `docs/audits/film-stock-accuracy-probe.py:36-37`).
- `Scripts/ci_scope.py` handles the untrusted `BASE_SHA` correctly: passed as an argv
  element to `git diff` with a `--` terminator, never through a shell. It writes only
  `engine=true|false` / `app=true|false` to `$GITHUB_OUTPUT`, so no output injection
  is possible.
- `Scripts/bake-catalogue.sh` uses `set -euo pipefail`, quotes every expansion, and
  derives paths from `basename`.
- Both workflows scope `permissions: contents: read`, use `pull_request` rather than
  `pull_request_target`, reference no secrets at all, and route
  `github.event.pull_request.base.sha` through an `env:` block instead of
  interpolating it into a `run:` string.
- `.gitignore` and a full-tree grep for `api_key`, `secret`, `password`, `token` and
  PEM headers found **no committed credentials**.
- The Baker is a separate `executableTarget` (`Package.swift:11`) and the app's
  `PBXSourcesBuildPhase` (`project.pbxproj:202-232`) links none of it. CI asserts
  this in its build step name (`ci.yml:98`).
