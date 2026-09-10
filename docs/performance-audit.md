# Performance and responsiveness audit

Audited 2026-09-09. Scope: startup, photo selection/decode, preview rendering,
stock switching, parameter dials, filmstrip, compare/loupe, presets, Scan/Print,
contact sheet, settings, image export and LUT export.

## Main list and implementation

| Priority | Flow / finding | Implemented improvement |
| --- | --- | --- |
| High | First photo and secondary previews constructed `Renderer` synchronously on the main actor, including shader compilation. | Added an asynchronous renderer factory; editor, thumbnail and contact-sheet setup use it. |
| High | Filmstrip refreshes and each Scan/Print card created another renderer, discarding pipeline and response caches. | One lazily created renderer is retained for editor secondary previews, separate from the main preview renderer. |
| High | Every canvas update scheduled a draw; each draw allocated and uploaded the whole image, including loupe-only movement. Every cell compiled its own display shader. | Rendered pixels have stable identity. Unchanged canvases do not redraw; loupe movement reuses the uploaded texture. Canvases share the display pipeline. Resize still requests a redraw. |
| High | Every dial render allocated two full preview textures and dispatched copy-only passes. | Retain one dimension-matched texture pair, refill input each time, replace the pair on resize, and skip copy-only passes without swapping textures. Actual pass ordering and shaders are unchanged. |
| Medium | The photo remained unavailable until thumbnail decoding finished. Older open tasks could also clear the loading flag for a newer selection. | Publish the decoded original preview before secondary decoding, allow editing immediately, and guard publication/loading/error state by request identity. Cancel obsolete thumbnail jobs. |
| Medium | Unchanged settings and stock assignments scheduled work; stock clamping wrote settings three times. | Ignore unchanged assignments and apply stock constraints in one settings update. Existing latest-value render coalescing and thumbnail debounce remain. |
| Medium | Launch and contact-sheet preparation read catalogue/reference data on the UI actor. | Perform that work off the main actor; avoid loading an already loaded editor catalogue again. |
| Medium | Preset rendering outlived sheet dismissal; output card keys did not identify the photo. | Cancel preset rendering on dismissal; invalidate Scan/Print previews when the new thumbnail input is ready. Check cancellation before queued renderer work and contact-sheet publication. |
| Medium | Export wrote potentially large files synchronously on the UI actor. | Write files on a utility task, preserve cancellation, and remove a newly written file if cancellation arrived during the write. LUT cancellation returns to the idle state. |
| Low | Render duration discarded whole seconds. | Report the complete elapsed duration, so slow frames remain visible in diagnostics. |

## Measurements

Command: `DYE_PHOTO_OPEN_AUDIT=1 swift test -c release --filter photoOpenAudit`.
The diagnostic uses a generated tagged Display P3 4032 × 3024 JPEG and a 2048-pixel
preview on this Apple Silicon Mac. It measures engine phases, not picker transfer,
SwiftUI presentation, or real-device touch latency. Three iterations are a small
sample, and driver caches were not purged between runs.

| Phase | Before, warm iterations 2–3 | After, warm iterations 2–3 |
| --- | --- | --- |
| Preview decode | 112.0–114.3 ms | 114.5–115.1 ms |
| Identity rerender | 13.4–14.3 ms | 6.9–7.0 ms |
| Serial diagnostic photo-open total | 159.5–161.7 ms | 153.8–154.3 ms |

First measured totals were 222.6 ms before and 232.0 ms after: this does **not**
establish a cold-start speedup. Initial renderer setup measured about 37–42 ms;
production UI call sites now move that synchronous work off the main actor.
The diagnostic intentionally still times synchronous initialization separately.
Moving thumbnail decoding after publication removes roughly 11 ms from the app's
path to showing the original preview; the serial diagnostic still includes it.

The expanded diagnostic also renders twelve Portra 400 exposure settings per
iteration: warm means were 20.7–21.0 ms after the changes. There is no matching
pre-change Portra measurement, so this is a baseline for future work, not a
claimed improvement. It also shows that full-quality preview rendering is not
proven to meet a 16.7 ms frame budget, much less an 8.3 ms budget.

Debug decoding measured around 2.9 seconds for the same JPEG, versus about 115 ms
in release. Use optimized builds for performance decisions.

## Verification

- Simulator build passed for arm64 and x86_64. App built and launched on iPhone 17
  Pro / iOS 26.5 simulator.
- Smoke-tested startup, loading a simulator photo, opening the stock selector,
  and opening/dismissing the contact sheet. Automated mouse drags did not change
  the dial value, so gesture responsiveness is not claimed as verified.
- 88 selected release tests passed, including catalogue golden images, identity
  bit preservation, colour management, RAW decode, preview downsampling, rendering
  budgets, tiled/untiled equality, export writers and cancellation.
- New regression checks repeated renders with different settings and dimensions
  against fresh renderers, guarding against stale ping-pong texture contents.
- The full debug suite was stopped because it started expensive offline Baker CLI
  jobs. Those unrelated baking tests were excluded from the completed run:

```sh
swift test -c release --skip 'bakerCLI|everyCurveSet|bakerRejects|portraCLI|spectralValidation|portraDevelopment|portraChromatic|spectralCLI|aDerivedStock|aMonochromeCurveSet|theMonochromeCollapse'
```

## Remaining opportunities requiring further measurement

1. **Decode and large-photo memory:** standard images still pass through a Float32
   Core Graphics buffer and a float16 conversion; RAW thumbnails decode the source
   a second time. Profile real JPEG, HEIF, transparent PNG, and camera RAW inputs.
   Consider a GPU colour-managed decode or deriving thumbnails from the decoded
   preview only after testing orientation, alpha, HDR and linear-light resampling.
2. **GPU-to-display handoff:** each edited frame still reads back to CPU memory
   and uploads into the canvas. A GPU-backed preview with explicit resource
   ownership and synchronization could remove these transfers. Current reuse
   retains two preview textures until resize or renderer release; measure retained
   memory as well as allocation reduction.
3. **Interaction quality:** measure frame pacing on 60 Hz and 120 Hz iPhones with
   rapid stock changes, long dial drags, compare and loupe. If GPU time remains too
   high, evaluate reduced-resolution rendering while dragging with a full-quality
   final render. Do not silently change grain/spatial appearance without review.
4. **Export:** tiling and cancellation already exist, but full-source decode and
   final encoding still occupy the renderer actor. Measure simultaneous editing
   and 48 MP export, memory peaks and thermal behavior before splitting ownership
   into another renderer or changing the writer. A separate queue alone does not
   make synchronous actor work concurrent.
5. **Secondary surfaces:** contact-sheet results regenerate on reopening and preset
   rows decode their small settings payloads again. Measure before adding broader
   caches; any cache needs photo/settings keys and a memory-pressure policy.
6. **Startup/settings:** SwiftData container creation remains synchronous at app
   startup. Measure cold launches with a large preset store before changing store
   initialization. Settings/glossary and haptics show no measured bottleneck;
   haptic generators are already reused.

Physical-device Instruments traces, Photos/iCloud download timing, and real-camera
memory/thermal tests remain necessary to make device-level performance claims.
