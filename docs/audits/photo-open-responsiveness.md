# Photo open responsiveness audit

Date: 2026-09-09. Scope: tap Photo → system picker → selection → first displayed photo.
The reported delay occurs both before the picker appears and after selection.
Device versus simulator is not yet specified.

## Evidence and limits

This is a source audit with an opt-in engine timing harness. It does not reproduce
the picker presentation delay or measure iPhone performance. No application
behavior was changed. The harness exercises the same engine calls and ordering
as `EditorModel.open`, followed by its scheduled identity render, using a
synthetic tagged Display P3 4032×3024 JPEG. It excludes Photos transfer, SwiftUI,
canvas presentation, thumbnail rendering, and non-identity Stock costs.

Run on a Mac with Metal:

```sh
DYE_PHOTO_OPEN_AUDIT=1 swift test -c release --filter photoOpenAudit
```

The harness is disabled during normal tests. Timings are diagnostics, not fixed
pass/fail thresholds across different machines. Three renderer instances expose
startup versus subsequent initialization costs; OS shader caches are not reset.

## Current critical path

1. `ActionRow` presents `PhotosPicker` with `.current` encoding.
2. Selection changes trigger `EditorView.task(id: photo)`.
3. `EditorModel.open` marks loading, then synchronously constructs `Renderer`
   on MainActor if needed, before awaiting Photos transfer.
4. Photos supplies the complete encoded `Data`.
5. The renderer decodes a 2048-pixel Preview and renders its identity comparison.
6. The renderer decodes the original bytes again at 192 pixels for thumbnails.
7. The model publishes input state and schedules both thumbnails and edited rendering.
8. The canvas remains in its loading state until the edited render publishes.
9. A newly created `FilmCanvas.Coordinator` compiles its display shaders and
   pipeline on MainActor during its first draw, then uploads pixels and presents.

## Findings, ordered by implementation priority

### 1. Synchronous GPU setup can block interaction

`EditorModel.swift:146`, `:471`, `:485`; `Renderer.swift:33–60`.
`Renderer` being an actor does not make its synchronous initializer asynchronous.
Initialization reads Metal source, builds a library, and creates 21 compute
pipelines. The first photo does this on MainActor before Photos transfer. Thumbnail
refreshes also construct a renderer inside a MainActor-inheriting Task, after a
200 ms debounce. That delay is not background execution.

Recommendation: initialize renderers away from MainActor and reuse a bounded set
for Preview and thumbnails. Deduplicate concurrent initialization, preserve actor
ownership of mutable caches, and propagate initialization failures. Consider
bundled precompiled Metal libraries as a later build-system improvement.

Expected benefit: avoid UI stalls after selection and during thumbnail refreshes.
Thumbnail initialization could interfere with a later tap, but a device trace is
needed to attribute the observed picker delay to it.

### 2. Thumbnail preparation unnecessarily delays the first photo

`EditorModel.swift:150–167`; `ImageDecoder.swift:61–117`.
The app serially decodes the original a second time before scheduling the edited
Preview. For ordinary formats the decoder creates an image from the source and
uses a colour-managed CGContext to scale it; a 192-pixel target does not request
an ImageIO decoder thumbnail. RAW takes the separate CIRAWFilter path twice.

Recommendation: prioritize the first edited frame, then prepare thumbnails.
Evaluate deriving the small input from the decoded linear Preview to avoid a
second source decode. Keep colour management, HDR, alpha, orientation, and export
behavior covered before changing the decoder. Moving work to another Task on
the same renderer actor alone does not guarantee it will stop delaying Preview.

### 3. Display pipeline creation repeats across canvases

`FilmCanvas.swift:61–97`; `CanvasView.swift:48–79`; `Filmstrip.swift:142–148`.
Every coordinator owns a separate pipeline compiled on first draw. Switching to
loading removes the photo branch, so reopening recreates its canvas. Filmstrip
cells each create another canvas, and the strip uses HStack rather than LazyHStack.
Every draw also creates a texture and uploads the full image.

Recommendation: share immutable display pipeline state per Metal device/pixel
format, prepare it off the UI actor, and retain the canvas while a loading overlay
is shown. Cache the uploaded image texture until pixels change. Treat laziness
for filmstrip cells as a separate measured change.

### 4. Loading feedback hides useful pixels and conflates phases

`EditorView.swift:43–50`; `CanvasView.swift:151`.
Loading replaces an existing photo, and the label says “Decoding…” even while
Photos may be transferring bytes or the renderer is initializing. An identity
image has already been rendered but remains hidden until the edited image lands.

Recommendation: retain the previous photo with clear loading feedback, distinguish
transfer from processing, and publish the selected photo as soon as a useful frame
is ready. If showing an unedited intermediate, label it until the Stock is applied.
Do not enable exporting the previous photo as though it were the new selection.

### 5. Superseded loads need explicit ownership

`EditorModel.swift:141–172`, `:510–532`.
The view cancels the old selection task, but `open` has an unconditional defer that
clears shared loading state. There is no cancellation check immediately after
transfer, and image generation changes only late in loading. Existing thumbnail
work can continue while the next image loads; preset thumbnail work is not
cancelled by `open`.

Recommendation: assign an import generation at entry, guard every state publication
and loading cleanup with it, check cancellation between expensive stages, and
cancel obsolete background thumbnail jobs. This prevents stale progress/errors
and wasted work during rapid selections. It is a code-level race risk, not a
reproduced explanation of the reported latency.

## Before-picker delay: unresolved

The normal Photo button directly invokes PhotosPicker; it performs no image decode
before presentation. The context menu uses a separate `.photosPicker` modifier.
This duplication is not evidence of a performance defect. Catalogue header loading
runs synchronously at editor startup, but payloads are lazy: do not assume it loads
all Colour Cubes. Haptics initialize on first press, another boundary to measure.

Capture an on-device Time Profiler / Hangs trace with timestamps for touch-up,
picker presentation, selection, transfer completion, renderer readiness, Preview
decode, first render completion, and first drawable presentation. Measure normal
button and context-menu entry separately; compare first and subsequent opens,
idle versus active thumbnails, local JPEG/HEIC versus iCloud-only assets, RAW,
and Debug versus Release. The app's current render-time badge omits most of these
stages and cannot establish photo-open latency.

## Recommended delivery sequence

1. Capture the two UI intervals and retain the engine baseline below.
2. Move renderer initialization off MainActor; reuse thumbnail renderers and
   display pipelines. Verify interaction during initialization.
3. Remove thumbnail preparation from the first-frame critical path; add generation
   ownership and cancellation checks.
4. Preserve canvas/loading feedback, then evaluate decode and texture optimizations.

Use an iOS UI/integration test seam for rapid A→B selection, cancellation, transfer
failure, and first-frame publication. The current package tests cannot exercise
`PhotosPickerItem` → `EditorModel` → SwiftUI → drawable presentation. An engine-only
test must not be presented as a regression test for picker responsiveness.

## Measured baseline

Apple M1 Pro, macOS host, Swift release build, synthetic 12 MP JPEG, identity
Profile. The opt-in test passed; its measured body took 0.56 s total.

| Stage | First instance | Second instance | Third instance |
| --- | ---: | ---: | ---: |
| Renderer initialization on MainActor | 42.3 ms | 2.6 ms | 2.6 ms |
| 2048-pixel Preview decode | 120.5 ms | 105.0 ms | 106.5 ms |
| Identity comparison render | 30.9 ms | 17.3 ms | 16.9 ms |
| 192-pixel source decode | 11.5 ms | 11.2 ms | 11.1 ms |
| Edited identity render | 11.9 ms | 12.5 ms | 12.6 ms |
| Total engine sequence | 217.2 ms | 148.7 ms | 149.7 ms |

Catalogue header loading for 17 Profiles took 6.6 ms. Initial renderer setup exceeds
a 16.7 ms frame budget on this host, while subsequent setup is much cheaper. The
Preview decode dominates this narrow baseline. Deferring the thumbnail decode
removes about 11 ms from this measured sequence; it does not by itself account for
a multi-second delay. No before/after improvement has been measured because this
change adds an audit and diagnostic only. Real photos, device hardware, transfer,
shader-cache state, display setup, and non-identity rendering can change the result.
