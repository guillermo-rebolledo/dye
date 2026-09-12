# Photographer release polish

The editor keeps its canvas, rail and four primary actions. This change addresses
the five release-review findings without changing the rendering pipeline.

- Applying a preset offers **Undo preset** in the editor. It restores the stock,
  every render setting and the values of bypassed adjustments. It is one-step
  undo: the next actual edit or successful photo import ends its availability.
  Failed preset validation and failed imports leave an existing undo intact.
- **Preview zoom** replaces the misleading 1:1 loupe label. A visible badge and
  accessible hint explain that exported photos have the full-resolution detail.
- A first-use, explicitly dismissed tip introduces compare, fine adjustment and
  reset. The active control has a visible **Reset** action when modified or bypassed.
  The control area can scroll when available height cannot accommodate it.
- The selected film stock has a short visual description. The full modelling
  explanation remains in an **About Modelled and Approx.** disclosure in the picker.
- **Stock reference** names the former Contact Sheet in the toolbar, screen and
  glossary. Its introductory text explains that it uses a sample image and does
  not change the edit, and points to Film Stock for choosing a look on your photo.

## Description evidence

Descriptions are of Dye’s starting models, not claims of photographic fidelity.
Colour, highlight and shadow descriptions were checked against the committed
[reference boards](../audits/film-stock-accuracy-review/README.md). The daylight
and tungsten copy follows the balance recorded in each Curve Set. The grain
comparisons use the committed model parameters:

| Stock | RMS granularity | Grain radius (µm) |
| --- | --- | --- |
| Linen 160 | 0.006 | 1.0 |
| Linen 400 | 0.008 | 1.2 |
| Newsprint 400 | 0.017 | 1.6 |
| Graphite 100 | 0.008 | 0.8 |

These model values are not a new physical validation. Preview size, exposure,
white balance, output choice and further adjustments can change the appearance.

## Validation

`python3 Scripts/check-preset-undo.py` compiles the real EditorModel, Parameter
bindings, PickedPhoto loading and snapshot implementation against FilmEngine on
macOS. Only the picker UI and SwiftUI previews are omitted. It checks restoration
across incompatible stocks, bypassed values, rejected presets, consecutive
applications, edit invalidation, reset of a bypassed control, failed import and
successful import. The existing `check-dial-mapping.py` CI entry point also runs
this check, so it needs no additional workflow step.

Simulator walkthrough on iPhone 17 / iOS 26.5 used a bundled waterfall photo:
first-use guidance, selecting Ash 100, applying a neutral preset, undoing back to
Ash 100, Preview zoom and its badge, and Stock reference with its explanation.
The stock descriptions update when selecting a different stock. This is a
simulator check; physical-device colour fidelity and performance are not claimed.

Normal text and the largest accessibility text size were inspected. Stage and
parameter labels occupy separate rows at accessibility sizes; the canvas remains
visible and Photo / More stay reachable. Dismissing the first-use tip survives an
app relaunch. The stock-modelling disclosure opens its complete explanation.

Passed locally:

- `python3 Scripts/check-preset-undo.py`
- `python3 Scripts/check-dial-mapping.py`
- `PROFILE_BAKER_EXECUTABLE="$PWD/.build/release/ProfileBaker" swift test --skip previewRenderAndStockSwitchStayWithinInteractiveBudgets` — 150 tests
- `swift test --skip-build --filter previewRenderAndStockSwitchStayWithinInteractiveBudgets` — 1 test, 2 stock cases
- Python CI-scope/site and accuracy-benchmark checks — 12 tests
- Debug iOS Simulator build and unsigned Release device archive
- `python3 Scripts/check-archive.py .build/Dye-polish.xcarchive`
- `git diff --check`
