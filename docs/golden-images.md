# Contact Sheet and Golden Images

Open **Contact Sheet** from the editor toolbar, even without choosing a photo.
Every bundled Profile renders the same 192 × 128 linear Rec.2020 reference at
`ContactSheetReference.settings`: fixed Seed 253, stock-default spatial effects,
and nonzero Vignette, Gate Weave and Frame Border. The reference contains a
12-stop neutral ramp, saturated and skin-coloured patches, fine detail and an
8× SDR white light against shadow. Review colour, shadow separation, highlight
rolloff, scattering, grain and framing together whenever the engine changes.
This synthetic reference is repeatable; also inspect real photos in the editor.

Golden Images are a separate automated gate at `Renderer.render`. Each Catalogue
Profile has a committed raw little-endian RGBA float16 snapshot (192 × 128,
Display P3 transfer-encoded, straight alpha). Comparison is bit-exact, including
HDR and negative values; there is no tolerance or automatic update in CI.

## Review and accept an intentional change

1. Run `swift test --filter catalogueRendersMatchGoldenImages`. A missing image or
   any changed bit fails. Investigate the engine/Profile change first.
2. Open the Contact Sheet on the base revision and changed revision. Compare all
   Stocks, particularly the effects named above. Inspect real photos and an EDR
   device as appropriate. Record the reason and visual observations in the PR.
3. Only after deciding the change is intended, explicitly record:
   `DYE_RECORD_GOLDENS=1 swift test --filter catalogueRendersMatchGoldenImages`.
4. Unset that variable and rerun the filtered test, then `swift test`. Commit the
   changed `.rgba16` files with the implementation and review explanation.

Recording writes to `Tests/FilmEngineTests/Fixtures/GoldenImages` in the source
checkout. Normal runs only read those files. New Catalogue entries require new
snapshots; never silently skip a missing file. GPU/compiler changes may produce
bit differences: investigate and document the environment instead of widening a
tolerance. The initial snapshots were recorded on Apple Silicon with Xcode 26.6.

## Editor checks

- Save a named Preset, terminate and relaunch, choose another photo, and apply it.
  Verify the Stock and all controls, including Geometry, return. Delete and relaunch
  to verify deletion. Presets use an on-disk SwiftData container; failed saves and
  unavailable Stocks report errors.
- Hold the canvas to show the Identity render with default settings. Release or
  cancel the gesture to return to the edit. VoiceOver offers a toggle action.
- Choose two different photos and change controls quickly. The thumbnail strip
  must show the latest photo/settings through each Stock; cancellation prevents
  an older thumbnail task from overwriting newer results.
- On an EDR-capable device, view HDR input using Identity. The float16 extended
  Display P3 canvas opts into EDR when its window's screen reports
  `potentialEDRHeadroom > 1`. Compare bright areas with SDR white. Repeat on an SDR
  display; no EDR is requested. Actual brightness depends on current headroom and
  system conditions. Simulator builds cannot validate physical highlight luminance.
