# The editor redesign

`design_handoff_dye_editor/` describes a new editing surface for Dye: a fixed
control deck under an always-visible canvas, replacing the vertically scrolling
stack of three Stage Cards in `FilmApp/FilmApp.swift`. This document is the
implementation spec for that handoff — what gets built, against which parts of
the engine, in what order, and what has to be decided before it can be finished.

> **The design reference has moved on.** The fixed-deck mockups this document was
> written against are no longer in the repo. The handoff folder now holds the
> rail that supersedes the deck:
> [`one-rail-redesign.md`](../design_handoff_dye_editor/one-rail-redesign.md) is
> the spec and
> [`Dye Editor - one rail.html`](../design_handoff_dye_editor/Dye%20Editor%20-%20one%20rail.html)
> is the reference. This document stays the record of what shipped, of where the
> fixed-deck handoff and the engine disagreed, and of how each was resolved.

The handoff is the source of truth for *appearance*. The engine is the source of
truth for *behaviour*, which is the handoff's own rule and is applied literally
below. Where the two disagree, §2 records the resolution rather than leaving the
conflict for whoever opens the file next.

**This is a presentation-layer change.** No shader, no Profile, no Curve Set and
no render path is touched. Three model-layer additions are needed and they are
listed in §5; all three are reporting, not rendering.

## Dial update — September 2026

All eleven numeric controls now use the handoff's shutter ticker pattern: a
moving graduated tape beneath a fixed 1.5 pt center hairline, with faded edges
and an amber neutral/stock detent. This supersedes the moving-indicator track
specified for continuous controls in the original handoff.

`ParameterDial` covers Exposure, Temperature, Tint, Exposure time, Development,
Bloom, Halation, Grain, Vignette, Gate weave, and Frame border, including the
parameter catalogue preview. Contrast filter discs and Scan/Print cards remain
selection controls. No stock `Slider` remains in the app.

Drag left to increase and right to decrease. Touching the control does not jump
the value. Continuous parameters use 9 pt per step; shutter speed retains 54 pt
per stop with thirds-of-a-stop steps; the Adjustments use 1.8 pt per step, which
is what keeps two hundred steps to about the same finger travel as everything
else on the deck (see the Adjust addendum). Where that pitch would draw the minor
ticks closer together than 4 pt, the row thins them to a fraction of the major
interval instead, so a tick row never reads as a solid band. Canvas adjustment uses the same direction
at half gain. Existing ranges, step sizes, 6 pt detent stick, limit haptics,
VoiceOver adjustment, reset animation and Reduce Motion behavior are retained.
The tape stops at its bounds and the end cap lights at the center hairline.
The dial keeps the 28 pt drawing / 44 pt hit area and fixed deck allocation.

Run `python3 Scripts/check-dial-mapping.py` to check the production mapping
across all numeric ranges, including a stock balance between two Kelvin steps.

## 1. Scope

Rebuilt: the editor screen and all four of its secondary surfaces.

| Surface | Today | After |
| --- | --- | --- |
| Editor | `EditorView`, scrolling `StageCard`s, stock `Slider`s | canvas + 316 pt deck, custom scrubber |
| Export | `ExportSheet`, `Form` | detented sheet, tile-grid progress, file record |
| Presets | `PresetSheet`, `List` | detented sheet, rendered thumbnails, summary lines |
| Contact sheet | `ContactSheetView`, `LazyVGrid` | full-screen paper, process-coloured indices |
| Stock picker | horizontal thumbnail row + menu `Picker` | 135 filmstrip inside the deck |

Deleted outright: `StageCard`, `StageArrow`, `LabeledSlider`, the `NavigationStack`
and its toolbar. The handoff earns no top navigation bar; Photo, Presets, Contact
Sheet and Export all move into the deck's 40 pt action row.

Kept unchanged: `FilmCanvas`'s Metal path and its EDR handling, `EditorModel`'s
render loop, thumbnail scheduling, export path and thermal observation.

Out of scope for the first pass, and tracked in §7: light mode, landscape and
iPad, and the Dynamic Type mock. The handoff describes all three but mocks none
of them.

## 2. Where the handoff and the engine disagree

Six conflicts, all resolved. The engine wins in every case except the two range
clamps, which are deliberate and are marked as such, because the handoff's numbers
were read from a snapshot of the app rather than from `RenderSettings`.

**Geometry ranges are 0–100 %, not 0–200 %.** §5 of the handoff gives Vignette,
Gate weave and Frame border a 0–200 % range. `RenderSettings.vignetteRange`,
`gateWeaveRange` and `frameBorderRange` are all `0.0...1.0`. Build 0–100 % in
5 % steps. The detent stays at zero and the `● OFF` treatment is unaffected.
Bloom, Halation and Grain really are `0.0...2.0`, so their 0–200 % with a detent
at 100 % is correct as written.

**The Catalogue has sixteen cells, not eleven.** The handoff names Identity plus
ten stocks in a curated order. `ProfileCatalogue.bundled()` reads every
`.filmprofile` in the resource directory and sorts by filename, which today is
fifteen Profiles: the ten the handoff names, plus `study-c41`, `study-e6`,
`study-bw-silver`, `study-bw-chromogenic` and `study-ecn2`. Those five are
synthetic foundation Profiles and their `displayName` says so.

**The filmstrip shows all sixteen.** The study Profiles are honest entries in the
Catalogue and each one names itself a study, so the strip does not need to hide
them and hiding them would need a metadata flag the Profile format does not have.
The strip is driven by the Catalogue in the order the Catalogue returns, and a
cell count is never hardcoded — a Profile added to the resource directory appears
in the strip with no change to the editor.

**Exposure and Temperature are clamped by the app, not the engine.**
`RenderSettings.exposureRange` is ±6 EV and `temperatureRange` is 1667–25000 K.
The current `EditorView` hardcodes ±3 EV and 2000–10000 K, and the handoff copied
those. The narrow ranges are the better control — ±6 EV on a 393 pt track is
1/50 EV per point and unusable — so keep them, but declare them as named editor
constants with a comment saying they are a UI clamp inside a wider engine range,
not the engine's limits. A value arriving from a Preset outside the clamp is
valid and must not be rejected; the scrubber parks at its wall and the readout
tells the truth.

**Exposure time is a stops-space control over a seconds-space setting.**
`RenderSettings.exposureSecondsRange` is 1/8000…3600 s. The dial moves in ⅓ stops
of `log2(seconds)` and formats as a shutter speed, which the existing
`exposureStopsBinding` and `shutterSpeed(_:)` already do correctly. Lift both out
of `EditorView` unchanged.

**The contrast-filter readout carries no sign.** The handoff shows
`Yellow  −1.0 stop`. `filterFactorStops` returns `log2(base / filtered)` and is
documented as positive, because every Contrast Filter subtracts light. The minus
sign in the mock is therefore a display invention, and a wrong one: the render
has already added the stop back, so nothing on screen got darker and a minus sign
says it did. Show the magnitude with no sign — `Yellow  1.0 stop` — and let the
caption, verbatim from `contrastFilterHint`, say the cost is already paid.

This is the one place the app's "signs are always present" rule does not apply.
That rule exists for bipolar values, where the sign carries direction. A filter
factor is unipolar and always a cost, so a sign would be decoration on a value
that only points one way. `none` reads as `No filter` with no number at all.

**The Lab sub-label has no Identity case.** The handoff's table covers scan,
print and reversal. `outputSubtitle` today returns `Display P3` for Identity.
Keep that string.

## 3. Architecture

```
EditorView                     canvas + deck, owns no parameter state
├─ CanvasView                  FilmCanvas + compare pill + render-time pill
│                              + empty gate, loading and loupe
└─ DeckView                    316 pt, fixed, never scrolls
   ├─ StageSelector            Light › Film › Lab
   ├─ StageSubLabel            live, one line, truncating
   ├─ ParameterRow             chips, clipped with a right-edge fade
   ├─ ActiveControl            112 pt: header, readout, track row, caption slot
   │  ├─ Scrubber              continuous parameters
   │  ├─ ContrastFilterDiscs   six glass discs
   │  ├─ OutputStageCards      two 62 pt cards
   │  └─ ShutterDial           ticker
   ├─ Filmstrip                replaces ParameterRow + ActiveControl
   └─ ActionRow                Photo · Presets · Contact Sheet · Export
```

### The state the deck needs and the model does not have

`EditorModel` owns the render. It has no notion of a selected stage or an active
parameter, and it should not acquire one — those are presentation state and
belong beside the view, not beside the render loop. Add an `@Observable`
`EditorSelection` holding the current stage, the active parameter identity, and
whether the filmstrip is open.

A **parameter** becomes a value type rather than a call site. Today each control
is a hand-written `LabeledSlider` with its range, step and formatter inline, and
its caption is a separate computed property. The deck needs to enumerate the
parameters a stage offers, ask each one for its chip label, its readout, its
detent and its caption, and render whichever one is active. Model it as a
`Parameter` struct carrying: identity, display name, a `Binding<Double>`, range,
step, formatter, detent, an optional live caption closure, and which control
draws it. Build the per-stage arrays from the model's conditionals —
`hasReciprocity`, `contrastFilters`, `developmentRange`, `hasBloom`,
`hasHalation`, `hasGrain`, `outputStages` — exactly as `EditorView` branches
today.

That struct is the whole redesign's load-bearing piece. Every conditional-
visibility rule, every caption and every format string in the current
`EditorView` moves into it verbatim and nothing else needs to know the rules.

### Custom drawing

The brief forbids stock UIKit controls for the scrubber and forbids non-Apple
rendering stacks. Draw the track, ticks, fill, anchor and indicator with `Canvas`
or a `Shape` stack, and drive it with a `DragGesture` whose translation is
relative — touching at x does not jump the value to x. The hit area is the full
deck width and 44 pt tall, taller than the 28 pt track it draws.

Recessed wells, raised faces and the 1 pt press travel come from a small set of
view modifiers built once from §10 of the handoff and reused. Do not scatter
shadow literals through the component files.

## 4. Behaviour that must be preserved

These are already correct in the current app and the redesign must not lose them.

- **Hold to compare** is a 150 ms `LongPressGesture` sequenced before a
  `DragGesture`, swapping `beforePixels` for `pixels`. The swap is instant. The
  existing named accessibility action is kept.
- **The conflict rule** between hold and the new canvas drag: 150 ms stationary
  engages compare, 8 pt of movement inside that window makes it a drag, and once
  compare engages movement is ignored until lift.
- **Glass and Print do not survive a change of Stock.** `stockChanged()` already
  clamps `developmentOffset` and resets `contrastFilter` and `outputStage`. The
  deck must re-derive its parameter list on every stock change, or it will keep
  showing an active control the new Stock does not have.
- **The thumbnail strip renders the whole Catalogue at the settings on screen**,
  debounced 200 ms, cancelling in flight. Cells with no entry in `thumbnails`
  draw the hatched `developing…` state and never a spinner.
- **Export is one at a time** and continues while the sheet is dismissed and
  while editing continues behind it.
- **A render is coalesced**, so a drag renders the latest values rather than
  every intermediate one. The scrubber writes to `settings` on every step and
  relies on this; it must not add its own throttle.

## 5. Model additions

Three, all reporting.

**The finished export needs a record.** `EditorModel.Export.finished(URL)` carries
a URL. The handoff's finished state shows pixel dimensions, megapixels, colour
space, byte count, tile count and elapsed seconds. Extend the case to carry a
value type holding those, populated where the export task already has them.

**The tile grid needs a shape.** `ExportProgress` gives `completedTiles` and
`tileCount`, which is enough, but `tileCount` is zero until the first tile
reports. Draw the grid only once `tileCount > 1`, and lay it out for an arbitrary
count rather than the mock's fixed 6×4. A one-tile export is the LUT and shows
no grid.

**The contact sheet needs to know the loaded Stock.** `ContactSheetView` takes no
parameters today. Pass the selected stock id so the grease-pencil circle can mark
it.

**Preset rows need thumbnails and summaries.** A 44×34 frame rendered through
each Preset is a real render per Preset, which nothing in the model does today.
Add a second thumbnail scheduler keyed by Preset rather than by Stock, with the
same 200 ms debounce and in-flight cancellation as `scheduleThumbnails()`.

Its input is the current photo when one is loaded, and
`ContactSheetReference.image()` when one is not. That fallback already exists,
is deterministic, is the contact sheet's own input, and at 192×128 is comfortably
larger than the 44×34 it draws into. It also carries saturated patches, shadows
and lights above SDR white, so a Preset's look is legible on it rather than
reading as a grey square. Each Preset renders at its **own** decoded settings, not
the settings on screen — a Preset row is a record of a saved look, not a preview
of the current one, which is the opposite of what the Stock filmstrip does.

The summary line (`Portra 400 · +0.3 EV · 5200 K · Print`) is derivable from the
decoded `RenderSettings` and needs no render. Build it so a row is complete and
readable before its thumbnail arrives, and so a Preset whose Stock has been
removed still shows its summary next to the error `applyPreset` already throws.

## 6. Build order

Each phase leaves the app shippable.

1. **Tokens and primitives.** Colours as Display P3 assets, type styles, the
   raised/recessed/pressed modifiers, the haptic helpers. No screens yet.
2. **The `Parameter` type**, with every range, step, format and caption moved out
   of `EditorView` unchanged. Verify against the existing app before the UI
   changes, so any regression here is visible while the old screen still renders.
3. **The scrubber**, with ticks, fill, anchor, detent stick, range wall and the
   full-width relative drag. This is the component the whole deck rests on.
4. **The deck**: stage selector, sub-label, parameter row, active control, action
   row, at a fixed 316 pt. The deck frame not moving is the acceptance criterion,
   and it is tested against Tri-X (three Film chips), Velvia (no Lab output
   choice) and Identity.
5. **The canvas**: letterboxed layout (`1j`), compare pill, render-time pill,
   empty gate, loading and error. Cut the navigation bar here.
6. **The filmstrip**, replacing the parameter row and active control in the same
   156 pt.
7. **Gestures**: canvas horizontal drag at half gain, pinch loupe, and the
   conflict rule. The loupe needs zoom and pan in `FilmCanvas`, which is the only
   place the redesign touches Metal.
8. **The sheets**: Export, Presets, Contact Sheet, with the model additions from
   §5.
9. **Accessibility**: Dynamic Type reflow where the canvas gives up the height,
   VoiceOver adjustable scrubber at ⅙-stop increments, filmstrip container with
   `.isSelected`, and the non-gesture equivalent for every gesture.

## 7. The loupe's non-gesture equivalent

The handoff routes it to "the Sheet action's long-press menu", but the action row
has four buttons and two of them could be called Sheet.

**It goes on Contact Sheet.** The action row splits cleanly into looking and
committing: Photo and Export change what exists, Presets and Contact Sheet change
what you can see. The loupe is looking, so it belongs with the other looking
action — tap Contact Sheet for the reference grid across every Stock, long-press
it for a loupe on your own frame. Putting a view mode behind Export would file a
way of inspecting under the button that writes a file, which is the category
error the rest of this design avoids.

Long-press on a button is a weak affordance on its own, so the loupe is also a
named accessibility action on the canvas, beside the compare toggle that is
already there. That is what actually satisfies the requirement: a user who cannot
pinch is unlikely to be served by a gesture that is also a long press. The menu
item is the discoverable route and the accessibility action is the reliable one.

Unbuilt by design, and not blocking: the light-mode pass, the landscape and iPad
right-hand column, and the large-text mock.

## 8. Acceptance

The redesign is done when, for every Stock in the Catalogue and for no photo at
all:

- the deck is 316 pt and its bottom edge does not move — not on a caption
  appearing, not on a stage with fewer parameters, not with the filmstrip open,
  and not at the largest Dynamic Type size, where the canvas gives up the height
  instead;
- every parameter the model exposes is reachable, and no parameter the model
  hides is shown as disabled;
- every number on screen is SF Mono with `.monospacedDigit()`, always united,
  signed wherever the value is bipolar and unsigned where it is a magnitude, and
  does not jitter mid-drag;
- every detent in §11 of the handoff fires `.rigid` once on arrival and sticks
  for 6 pt;
- the canvas surround is `#050505` in every state and every appearance;
- every gesture has a non-gesture equivalent;
- stage and parameter switching are 80 ms and 60 ms with no spring, and Reduce
  Motion removes the animation without removing the haptic.

## Source of truth

Behaviour, ranges and caption copy: `FilmApp/EditorModel.swift`,
`FilmApp/FilmApp.swift`, `FilmApp/ExportSheet.swift`, `FilmApp/PresetSheet.swift`,
`FilmApp/ContactSheetView.swift`, `Sources/FilmEngine/RenderTypes.swift`,
`Sources/FilmEngine/Profiles/FilmProfile.swift`, `Curves/*/stock.json`.

Appearance: `design_handoff_dye_editor/README.md`, and the rail that supersedes
this deck in `design_handoff_dye_editor/one-rail-redesign.md` and
`design_handoff_dye_editor/Dye Editor - one rail.html`, screens `3a`–`3d`. The
fixed-deck mockups this document was written against, screens `1a`–`1q`, are no
longer in the repo; §2 below is the surviving record of what they specified.


## Minimal UI — September 2026

The editor keeps control names, values and dial marks, with explanations moved to
Settings → Glossary. The glossary is searchable and includes stock-specific
context for available controls, gestures, film terms and export options.

The standard deck is 268 pt (48 pt shorter); the filmstrip gets an additional
28 pt and accessibility text sizes retain their extra space. Errors add a
scrollable message region rather than displacing controls. Action icons retain
VoiceOver names and 44 pt targets. A Settings gear is available before import.

Shared control surfaces use flat fills and subtle borders. Export uses compact
progress and choices, preserving original-date fallback and save status. Presets
and Contact Sheet omit instructional copy. Render timing and the persistent
compare hint no longer overlay the photo; comparison still shows “Original”.

## Addendum: the Adjust stage

Added after the redesign shipped, and the one place this spec's "presentation-layer
change" rule does not hold: the deck has a fourth stage, **Adjust**, and it is
backed by a new Pass. [`adjustments.md`](adjustments.md) is the source of truth
for both; what follows is only what changed here.

- `EditorStage` has four cases and the stage selector draws four segments. The
  deck stays 316 pt: the Adjust stage's eight chips overflow into the parameter
  row's horizontal scroll, which the row already provided for.
- The eight parameters are all dials, ±100 in steps of 1, detent at 0, and
  every Stock offers every one of them, because the Pass acts on whatever the
  Output Stage returned. Zero reads `0`, not `+0` and not `OFF`: it is bipolar
  and the detent is the neutral setting.
- They are the one family with a pitch of their own: **1.8 pt per step**, not the
  deck's 9. The step stays at the 1 a photo editor's ±100 readout expects, so at
  the ordinary pitch the range is 1800 pt of finger, five screen widths, and a
  comfortable swipe reaches ±15 of a ±100 control. At 1.8 pt the range is 360 pt,
  which is what Grain's 0…200 % already costs.
- Each carries a **bypass**, on the right of the readout line: a control can be
  switched off and back on without losing its value, which is the question a
  photo editor asks most of an adjustment. It appears only when there is
  something to switch. Off writes zero to the settings and stashes the value in
  the editor, so the render, the Export and a saved Preset all see a control that
  is genuinely not applied; moving the dial gives it back at the new value, and
  applying a Preset clears every stash. It is not a reset — reset is still the
  chip's long press, and it throws the value away.
- Exposure, Temperature and Tint stay on the Light stage and are not repeated.
  They change the light the film received; the Adjust stage changes the scan.
- The Preset summary line gains one word, `adjusted`, when any of the eight is
  off zero, and the glossary's LUT entry says the cube carries them, because it
  does. The captions reach the glossary through the same path as every other
  control's, under an `Adjust` section of their own.

