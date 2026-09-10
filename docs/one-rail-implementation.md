# One-rail editor implementation

## Persistent Stock header (September 2026)

Stock identity now stays above the adjustment rail. Stock and Output open explicit
browsing sheets and never replace the rail. Dismissal preserves the active dial;
stock changes reconcile the available dial list. Contrast filters use the stepped
adjustment tape with named readouts. Stage jumps sit beside the parameter name,
with a separate 44 pt target. The default deck is 318 pt (388 pt at accessibility
text sizes), including a 56 pt Stock header that grows to 112 pt.

This supersedes the takeover behavior and 262 pt dimensions below and in the
original handoff. The renderer pipeline and stock-dependent setting rules remain
unchanged. The updated dial/selection checks and simulator build pass. Live simulator
inspection confirmed the Identity/Stock header, stock switching returning to
Exposure, and Scan/Print switching returning to Grain. Automated swipe attempts
did not move the simulator rail; physical touch scrolling and the expanded
accessibility layout still need device review.


The current editor follows `design_handoff_dye_editor/one-rail-redesign.md` and
screens 3a–3d in its bundled HTML. `editor-redesign.md` remains the history of the
previous deck and the source for the unchanged sheet treatments.

## Screen coverage

- **Editor:** 262 pt deck (276 pt at accessibility text sizes), pipeline-ordered
  snapping pucks, group jump menu, centred mono readout, resettable parameter name,
  tick-only tape, modified dots, and a 58 pt floating action capsule.
- **Stock:** live editor thumbnails in a 104 pt sprocketed strip with 96 × 60 pt
  frames, process edges and legend. Controls and an end-of-strip swipe continue
  to the following parameter. The deck and action bar keep their height.
- **Scan / Print:** two separately rendered previews from the current photo and
  settings. Selecting a card changes the real output setting; preview rendering
  never mutates it. Continue to controls leaves the takeover.
- **Empty, decoding and errors:** existing gate treatment; actionable import;
  bounded, scrollable error text above the fixed deck. No resting compare pill.
  ORIGINAL appears only during comparison, and render timing only during a drag.
- **Presets and Export:** existing save/apply/export behavior and surfaces retained.
  Shared sheets can expand to a large detent for constrained heights. Export
  choices, progress, cancellation, failures and completed records keep their
  existing state machine.
- **Contact Sheet:** adaptive columns with larger cells at accessibility text
  sizes; all bundled stocks retain real rendered reference frames.
- **Settings and Glossary:** shared deck/ink palette, searchable explanations,
  stock-specific captions, and a new explanation of rail navigation.

## Resolved differences and platform support

The engine remains authoritative. Reversal stocks still expose Vignette, Gate
weave and Frame border because these are stock-independent geometry operations.
Only Scan / Print disappears. The rail is not artificially shortened to hide
working controls. Conditional film controls retain the model's existing rules.

The tape keeps the established 9 pt ordinary, 1.8 pt Adjustment and 18 pt shutter
step mapping, parameter ranges, quantisation and sticky detents. Major marks are
six ordinary steps apart; shutter marks remain one stop apart. Existing word
formats such as “neutral”, “none” and “push +0.4” remain plain text.

Liquid Glass uses the native iOS 26 API and a shared selected-lens identity.
Building the app requires Xcode 26 or later for the Liquid Glass symbols; the
app CI job explicitly selects Xcode 26.3 on macOS 15. Runtime availability guards
preserve the iOS 17 deployment target. iOS 17–18 use a material fallback. Reduce Transparency replaces blur with an
opaque capsule; Increase Contrast adds its edge. Reduce Motion retains haptics.
The rail offers both an adjustable accessibility element and individually named,
selected parameter buttons. Reset, compare and loupe retain named actions.

The reference leaves landscape and iPad unspecified. Wider-than-tall windows use
a horizontal rail in a side panel (up to 393 pt); portrait tablet windows cap the
control width at 560 pt. The canvas takes the remaining space, and the action bar
stays above the home indicator.

## Validation

- `swift test --skip previewRenderAndStockSwitchStayWithinInteractiveBudgets`:
  97 tests passed, including deterministic catalogue bakes and renderer/export
  tests.
- `swift test --skip-build --filter previewRenderAndStockSwitchStayWithinInteractiveBudgets`:
  passed; best warm preview approximately 35 ms on the validation machine.
- `python3 Scripts/check-dial-mapping.py`: passed. Compiles the production mapping
  and selection types, checks detents/ranges/step mappings, stage jumps, takeover
  exit, unavailable-stage handling, empty lists and stock-list reconciliation.
  This check is also included in CI.
- iOS Simulator Debug app build: passed with Xcode 26.6 and deployment target 17.
- Live iPhone simulator review: empty/imported photo, direct parameter selection,
  group jump, Stock and stock switching, empty/saved Presets, Export choices and
  completed LUT, Contact Sheet, Settings and Glossary detail. Compared against
  the HTML reference rendered in Safari. iPad portrait and landscape layouts
  were also inspected at the largest accessibility text size. The tablet
  Scan/Print takeover was checked with real previews and a successful switch to Print.

Physical haptic feel and the older-iOS material fallback require device review;
they are not established by an iOS 26 simulator build.
