# Handoff: Dye — iOS film emulation editor

## Overview
A redesign of Dye's editing surface. The current app (`FilmApp/FilmApp.swift`) is a vertically scrolling stack of three stage cards using stock SwiftUI `Slider`s. This design replaces that with a **fixed-height control deck** under an always-visible canvas: the photo never scrolls away, nothing requires a second hand, and one control is active at a time.

The engine is unchanged. Every control, range, caption and conditional-visibility rule below was read out of `FilmApp/EditorModel.swift`, `FilmApp/FilmApp.swift` and `FilmApp/ExportSheet.swift` — this is a presentation-layer change only.

## About the design files
`Dye Editor.dc.html` is a **design reference written in HTML**, not production code. It is a flat canvas of 17 static mockups inside iPhone frames. Do not port the HTML, the React runtime, or `ios-frame.jsx`. The task is to build these screens in **SwiftUI (iOS 17+)** against the existing `EditorModel`, using custom drawing where noted — the brief forbids non-Apple rendering stacks and stock UIKit controls for the scrubber.

Open the file in a browser to see the screens; each is labelled with a stable id (`1a`…`1q`) that this document references.

## Fidelity
**High-fidelity.** Colours, type sizes, control heights and spacing are final and should be matched. The photograph in every frame is a **synthetic placeholder** (`assets/reference.png`) and the per-stock "renders" are CSS filter approximations — ignore them entirely, the real renderer produces the actual pixels.

---

## 1. Layout architecture

Portrait iPhone 15/16 Pro, 393 × 852 pt.

```
safe-area top
├─ CANVAS            flexible, ≥55% of display   #050505 surround
│                    photo aspect-fit, full width, centred
└─ DECK              316 pt fixed, never scrolls, contents swap
   ├─ stage selector   36 pt
   ├─ sub-label        14 pt   (live, one line, truncates)
   ├─ parameter row    34 pt
   ├─ active control  112 pt
   └─ action row       40 pt
   + 10 pt top padding, 16 pt horizontal, home-indicator inset below
```

Vertical gap between deck sections: **10 pt**. Deck background `#121214`, top border `0.5 pt rgba(255,255,255,0.08)`.

**The deck's frame never moves.** Not when captions appear, not when a stage has fewer parameters, not when the stock filmstrip opens. Only its contents change.

### Canvas: letterboxed, not full-bleed — recommended
Screens `1i` (full-bleed) and `1j` (letterboxed) mock both. **Build `1j`.** Reasons, in order: the whole frame stays visible (you cannot judge a vignette or frame border whose corners are hidden); the surround is a constant `#050505` so the eye has a fixed black reference for HDR highlights; and a translucent deck is tinted *by the photo*, so the chrome changes colour as you grade and stops being neutral. Cost is ~60 pt of image height on a 4:3 frame.

---

## 2. Stage selector

Three segments — **Light**, **Film**, **Lab** — in one milled trough, always visible, one tap to switch. Between them, a `›` chevron in `rgba(242,240,236,0.3)`: left-to-right **is** the order light travels.

- Trough: `height 36`, `radius 11`, `bg #0D0D0F`, `padding 3`, `box-shadow: inset 0 1px 2px rgba(0,0,0,.8), inset 0 0 0 .5px rgba(255,255,255,.05)`
- Selected segment: `height 30`, `radius 8`, `background linear-gradient(#2A2A2F → #1F1F23)`, `box-shadow: inset 0 1px 0 rgba(255,255,255,.12), 0 1px 2px rgba(0,0,0,.7), 0 0 0 .5px rgba(255,255,255,.07)`, SF Pro 13 semibold `#F2F0EC`
- Unselected: no background, SF Pro 13 medium `rgba(242,240,236,0.55)`
- Chevron column width 14 pt

Sub-label below, SF Pro 11/14, `rgba(242,240,236,0.5)`, centred, single line with tail truncation. Content per stage:

| Stage | Sub-label |
| --- | --- |
| Light | `Light as it reached the emulsion on the day.` |
| Film (stock loaded) | `{displayName} · {process.displayName} · balanced for {balance} K` |
| Film (identity) | `No film: the working space passes straight through` |
| Lab (scan) | `Scan · Display P3` |
| Lab (print) | `Print · enlarged onto RA-4 paper · Display P3` |
| Lab (reversal) | `Reversal · the film is the final image · nothing to scan or print` |
| No photo | `No photo loaded` |

---

## 3. Parameter row

Horizontal row of chips, 34 pt tall, `gap 5`. **Clipped, not scrolling** — `overflow hidden` with a right-edge fade `mask-image: linear-gradient(90deg, #000 92%, transparent)`. Prefer fitting; the fade is the overflow tell of last resort.

Chip: `height 34`, `padding 0 9`, `radius 9`, name in SF Pro 12 medium, value in SF Mono 12 medium with tabular figures, `gap 5` between them.

| State | Background | Name | Value | Extra |
| --- | --- | --- | --- | --- |
| default | `#17171A`, `inset 0 0 0 .5px rgba(255,255,255,.07)` | `rgba(242,240,236,.62)` | same | — |
| modified | same | `rgba(242,240,236,.85)` | `#F2F0EC` | 5 pt amber dot |
| active | `linear-gradient(#2A2A2F → #1F1F23)`, `inset 0 1px 0 rgba(255,255,255,.14), 0 1px 3px rgba(0,0,0,.6), 0 0 0 .5px rgba(255,255,255,.1)` | `#F2F0EC` | **accent** | dot if also modified |
| unavailable | default at `opacity 0.35`, value `—` | | | |

Tap selects as active control. **Long-press or double-tap resets to default**: `.rigid` haptic, value animates home in 160 ms ease-out (instant under Reduce Motion), the dot fades.

### Persistent slots
Two things are modes, not values, and occupy fixed positions at the **left** of the row so they never scroll away:

- **Stock** (Film stage): 26×24 thumbnail with a 2 pt process-coloured bottom edge + stock name. Tapping opens the filmstrip.
- **Scan / Print** (Lab stage, negative stocks only): a miniature segmented control, `height 34`, trough `#0D0D0F` `radius 9`, segments `padding 0 8`. Selected reads in **accent** when it departs from the default (`scan`).

---

## 4. Active control (112 pt)

```
header       16 pt   name (SF Pro 13 medium) · right-side tag (SF Mono 10 caps, +8% tracking)
readout      34 pt   SF Mono 34/34 medium, tabular, letter-spacing −0.5, #F2F0EC
                     unit trailing in SF Mono 15, rgba(242,240,236,.5)
track        28 pt
caption slot 28 pt   RESERVED — SF Pro 11/14, rgba(242,240,236,.62), max 2 lines
```

The caption slot is **always present and always 28 pt**, empty at rest. This is option A, and the recommendation. Option B — an ⓘ popover floating the caption over the canvas — is mocked and annotated in `1m` and rejected: it covers the picture, and captions that change live with the value (Temperature, Exposure time) need to be readable *while* dragging, when a second tap is impossible. Keep the ⓘ glyph in the header as the VoiceOver/Dynamic-Type affordance only.

### Track
`height 28`, `radius 7`, `background #0B0B0D`, `box-shadow: inset 0 1px 3px rgba(0,0,0,.9), inset 0 0 0 .5px rgba(255,255,255,.06)`.

- Minor ticks: 1 pt lines `rgba(255,255,255,.14)`, inset 6 pt vertically, one per step
- Major ticks: 1 pt `rgba(255,255,255,.28)`, inset 2 pt, one per stop / decade
- Fill from the anchor (zero for bipolar, left end for unipolar) to the value: `accent / 0.28`
- Anchor line: 2 pt `rgba(242,240,236,.5)`; when the value **is** on a detent the anchor becomes solid accent with `0 0 8px accent/.8` glow
- Indicator: 4 pt wide, extends 4 pt above and below the track, `radius 2`, `linear-gradient(#FFFFFF → #D8D6D2)`, `box-shadow: 0 0 0 .5px rgba(0,0,0,.8), 0 1px 3px rgba(0,0,0,.8)`; mid-drag it goes flat `#fff` and gains `0 0 12px accent/.5`

**Draggable from anywhere in the deck's width**, not just on the indicator — the hit area is the full 393 pt row, 44 pt tall. Drag is relative: touching at x does not jump the value to x.

| State | Reference |
| --- | --- |
| rest, mid-drag, at-detent, at-range-limit, disabled, bipolar, shutter dial | `1q`, scrubber block |

At the range limit the indicator parks 2 pt inside the end, the end wall lights to `rgba(242,240,236,.6)`, `.heavy` haptic once. **No rubber-band, no bounce.**

### Discrete controls swap the track
Not everything is a scrubber. The active-control area keeps its 112 pt but changes what fills the track row:

- **Contrast filter** (`1d`): six 30 pt glass discs — radial highlight at 35%/30%, dark lower rim `inset 0 -2px 4px rgba(0,0,0,.5)`, drop shadow. Selected gets `0 0 0 1.5px accent, 0 0 0 4px #121214`. "none" is an empty ring. Readout names the glass and its published factor (`Yellow  −1.0 stop`).
- **Scan / Print** (`1f`): two 62 pt cards side by side, each with a one-sentence description of the picture it produces. Selected card gets `0 0 0 1px accent/.6`.
- **Exposure time** (`1q`, shutter dial): a **ticker**, not a slider. Speeds scroll under a fixed 1.5 pt hairline at the centre in ⅓-stop steps, masked at both ends. The stock's reciprocity threshold is marked in accent.

---

## 5. What each stage contains

Ranges and conditional visibility are exactly what `EditorModel` exposes — read them from the profile, do not hardcode.

### Light
| Parameter | Range | Step | Format | Detent |
| --- | --- | --- | --- | --- |
| Exposure | −3…+3 EV | ⅙ stop | `%+.1f EV` | 0 |
| Temperature | 2000…10000 K | 50 K | `%.0f K` | the stock's `metadata.balance` |
| Tint | −100…+100 | 1 | `neutral` / `%+.0f magenta\|green` | 0 |
| Exposure time | `RenderSettings.exposureSecondsRange`, in **stops** | ⅓ stop | `1/125 s`, `4 s`, `2 min` | the reciprocity threshold |

Exposure time appears **only** when `model.hasReciprocity`. Captions come from `balanceHint` and `reciprocityHint` verbatim — they are live and change as the value crosses the stock's balance or threshold (`.medium` haptic, 90 ms text crossfade).

### Film
Sub-label is live. Parameters, all conditional:
- **Contrast filter** — `!model.contrastFilters.isEmpty` (B&W stocks with a measured spectral sensitivity only)
- **Development** — `model.developmentRange != nil`; step 0.1; formats `push +1.0` / `normal` / `pull −1.0`; detented at 0 (`box`)
- **Bloom** — `model.hasBloom`, 0–200 %, step 5 %, **detent at 100 %**
- **Halation** — `model.hasHalation`, same
- **Grain** — `model.hasGrain`, same

100 % is the stock's own modelled value; above it the user is knowingly exaggerating, and the detent is what tells them where the line is. Stocks hide some of these entirely (Tri-X in `1d` shows three chips, not five) — the row just has more air. `1e` shows a reversal stock; `1d` a B&W one. **The deck must survive both without moving.**

### Lab
- **Scan / Print** — persistent slot, present only when `model.outputStages` is non-empty (negative stocks carrying print variants). Absent for reversal and identity.
- **Vignette / Gate weave / Frame border** — 0–200 %, step 5 %, default 0, detent at 0. Zero reads `none` / `steady` / `none` in dimmed type with an accent `● OFF` tag and the indicator parked at the left wall. **Off must look off.**

---

## 6. Canvas chrome

Three things, nothing else. No top navigation bar anywhere in the app — nothing earned it; Photo, Presets, Contact Sheet and Export all live in the thumb-reachable action row.

- **Compare pill**, top-left, 10 pt inset: `height 24`, `padding 0 10`, `radius 12`, `rgba(10,10,12,.55)` + `backdrop blur(12)`, `inset 0 0 0 .5px rgba(255,255,255,.14)`, SF Pro 11 medium `rgba(242,240,236,.85)`, text `Hold to compare`.
  **Held** (`1g`): pill inverts to solid `#F2F0EC` with `#111` text reading `Original` — the only light surface in the app, and it means "not graded". The render-time pill hides. The whole deck drops to `opacity 0.6`. The **image swaps instantly, no crossfade** — a fade lies about what you are comparing. Pill inverts over 120 ms. `.light` haptic on engage and release. VoiceOver gets the existing named toggle action.
- **Render-time pill**, bottom-right: `height 22`, SF Mono 11 tabular, `18 ms`. **Keep it** — it is an instrument reading that makes "live" credible. Fades to 40 % after 2 s idle.
- Nothing else.

### Non-editing states
- **Empty** (`1h`): the canvas draws an empty gate — 4:3 box, `inset 0 0 0 1px rgba(255,255,255,.08)`, 135° hatch at 2 % white, `Open a photo` (SF Pro 17 semibold) over `Choose a photo to begin.` (13, 50 %). Deck present but flattened: chips read `—`, the track has no indicator, buttons lose their raised face. Only two actions stay live — **Photo**, promoted to the app's single amber primary button, and **Contact Sheet**, which needs no photo.
- **Loading**: `Decoding…` in the gate, same geometry.
- **Error**: one line, SF Pro 11, `oklch(0.72 0.17 25)`, in the caption slot. It does not displace the deck.

---

## 7. Gestures

| Gesture | Verdict | Behaviour |
| --- | --- | --- |
| Long-press ≥150 ms on canvas | **primary, existing** | Hold to compare |
| Horizontal drag on canvas | **add** | Adjusts the active parameter at **half the scrubber's gain** — it is the fine control. A transient readout pill appears centred at the top of the frame while dragging. Engages after 8 pt of movement. |
| Pinch | **add** | 1:1 loupe for judging grain and halation at pixel pitch. Snaps back on release. Non-gesture equivalent: loupe toggle in the Sheet action's long-press menu. |
| Vertical swipe to cycle stages | **cut** | Stages are already one tap away, vertical swipes fight sheet dismissal, and a diagonal drag would change exposure *and* stage. |

**Conflict rule:** hold requires 150 ms stationary; a touch that moves 8 pt inside that window is a drag. Once compare engages, movement is ignored until lift. See `1k`.

---

## 8. Stock filmstrip (`1c`)

The hero component. When the Stock slot is tapped, the filmstrip **replaces the parameter row and the active control** — same combined 156 pt, deck frame unmoved — because a live 100×80 thumbnail *is* the control and is far bigger than a scrubber. A `Controls` button returns.

It is drawn as a real 135 strip: full-bleed to the deck edges, `#0B0B0D`, sprocket rebates top and bottom (`repeating-linear-gradient(90deg, transparent 0 6px, #1E1E22 6px 14px, transparent 14px 22px)`, 6 pt tall). Cells are 100×80, `radius 3`, with:
- a 3 pt bottom edge in the **process colour**
- the catalogue index in SF Mono 9 at top-left, `rgba(255,255,255,.75)` with a 3 pt black text shadow
- name beneath in SF Pro 11 medium
- **selected**: `0 0 0 1.5px accent, 0 0 0 4px #121214`, name in accent
- **still rendering**: hatched `#17171A`/`#1C1C20` base with `developing…` in SF Mono 9 — never a spinner

Below the strip, a process legend (dot + label) and the `Controls` button. Right edge of the strip is masked `linear-gradient(90deg, #000 88%, transparent)`.

Eleven entries: Identity (no film), Portra 400, Cinestill 800T, Provia 100F, Velvia 50, Tri-X 400, T-Max 100, Vision3 50D, 250D, 200T, 500T. Stocks with `metadata.derivedFrom` show their provenance note in the caption slot on selection ("The same emulsion as Vision3 500T, modelled without its remjet backing.").

---

## 9. Secondary surfaces

All are **detented sheets at 500 pt** that leave the photo visible above — you are not grading while in them, but you may want to glance at the frame. Sheet: `#141416`, `radius 22 22 0 0`, `box-shadow: 0 -1px 0 rgba(255,255,255,.1), 0 -20px 60px rgba(0,0,0,.6)`, 36×5 grabber, 20 pt horizontal padding. Header: title SF Pro 20 semibold + `Done` in accent 15.

### Export (`1l`, `1m`, `1n`)
- **Idle**: Format segmented (HEIF / JPEG / 16-bit TIFF), Colour segmented (Display P3 / sRGB), footnote from `ExportSheet.photoFooter`. Two actions: **Export photo** (primary amber) and **Export LUT (.cube)** (secondary). The LUT footnote is verbatim from the repo, with `no grain, halation, bloom, micro-contrast or vignette` set bold — one bolded clause, no warning icon. Honesty is delivered in the same plain voice as the parameter captions.
- **Rendering**: progress drawn as what it is — a 6×4 grid of tiles filled in render order, current tile at 50 % accent, remaining at `rgba(255,255,255,.08)`. Readout `tile 7 of 24`, the number in accent, SF Mono tabular. Format and colour dim and lock. **Cancel** is the only destructive button: accent-red *text* on the standard raised face, never a red slab. `Done` disabled while running. Editing continues behind the sheet.
- **Throttled**: a plain row with an amber dot — the same colour that elsewhere means "the film's own value", here meaning "the engine chose for you". Copy from `ExportSheet.thermalNote`. Information, not error: no thermometer, no yellow.
- **Finished**: the file as a record — `portra-400.heif`, `8064 × 6048 · 48 MP · Display P3 · 31.2 MB`, `24 tiles · 14.8 s`, all SF Mono — with a thumbnail, one amber **Share**, and a quiet `Export another`.

### Presets (`1o`)
Name field (amber caret) + amber **Save** on one line, then a helper sentence naming exactly what will be kept: *"Saves Portra 400 · Print and every setting as they are now."* Rows are 60 pt: 44×34 thumbnail rendered through the preset, name SF Pro 14 semibold, summary in SF Mono 11 (`Portra 400 · +0.3 EV · 5200 K · Print`). Swipe-to-delete uses **system red** — destructive stays system-conventional so it is never confused with the amber "film's own value". Empty state: *"No presets yet. Name the current look above to keep it."*

### Contact Sheet (`1p`)
Full screen, no deck — you are not grading. Header line `Fixed HDR reference · all Stocks · Seed 253` in SF Mono 11. A single dark paper `#111113` with sprocket strips top and bottom, 3-up adaptive grid of 4:3 frames, each with its name and its index numbered in that stock's **process colour**. One **grease-pencil circle** in film-base orange marks the stock currently loaded in the editor, with a hand-set `this one` — the only decoration in the app, and it is doing a job. Close is a single machined ×.

---

## 10. Design tokens

### Colour
| Token | Value | Use |
| --- | --- | --- |
| `canvas` | `#050505` | behind the photo, in every mode |
| `deck` | `#121214` | deck surface |
| `sheet` | `#141416` | modal sheets |
| `well` | `#0D0D0F` / `#0B0B0D` | segmented troughs / scrubber track |
| `chip` | `#17171A` | resting chips, disabled buttons |
| `raised` | `linear-gradient(#2A2A2F → #1F1F23)` | pressable faces |
| `raised-icon` | `linear-gradient(#26262B → #1C1C20)` | small icon buttons |
| **`accent`** | **`oklch(0.74 0.15 55)`** | detents, defaults, loaded stock, primary action |
| `accent-pressed` | `oklch(0.62 0.15 55)` | pressed primary |
| `ink` | `#F2F0EC` | primary text, the "Original" pill |
| `destructive` | `oklch(0.72 0.17 25)` | Cancel text |
| `delete` | `oklch(0.55 0.19 25)` | swipe-to-delete slab |

Text opacities on dark: primary `#F2F0EC`, secondary `.7`, tertiary `.55`, quaternary `.4`, disabled `.3`.

**Why film-base orange.** It is the colour of an unexposed C-41 negative's mask, so it reads as *"this is the film's own value"* — which is exactly what a detent, a default and the loaded stock all mean. It sits far from skin and sky, so it never argues with the grade. Safelight amber is more saturated and would compete with HDR highlights. Ship these as Display P3 assets.

**One accent only.** It means "the film's own value" or "primary action" — never status. Destructive is system red.

### Process colours
Same lightness and chroma as the accent so none of them shouts:
`C-41 oklch(0.74 0.15 55)` · `E-6 oklch(0.74 0.11 235)` · `B&W silver oklch(0.82 0 0)` · `B&W chromogenic oklch(0.82 0.03 80)` · `ECN-2 oklch(0.74 0.11 165)`

### Type
| Role | Face | Size / leading | Weight |
| --- | --- | --- | --- |
| readout | SF Mono | 34 / 34, tracking −0.5 | medium |
| unit, secondary numerals | SF Mono | 15 | medium |
| chip value | SF Mono | 12 | medium |
| tag (`● DETENT`) | SF Mono | 10, tracking +8 %, caps | medium |
| stage, control name | SF Pro | 13 | semibold / medium |
| chip name, sheet body | SF Pro | 12–15 | medium |
| caption, sub-label | SF Pro | 11 / 14 | regular |
| action label | SF Pro | 10 | medium |

**Every number in the app is SF Mono with `.monospacedDigit()`.** Signs and units are always present (`+0.0 EV`, never `0`). Numbers must not jitter while dragging — this is why the readout is fixed-width and the unit is a separate trailing run.

### Metrics
Spacing 4 / 5 / 6 / 10 / 14 / 16 / 20. Radii: chip 9, segment 8, trough/track 7 · 11, button 11–12, sheet 22, filmstrip cell 3. Minimum hit target 44 pt — chips are 34 pt tall with a 44 pt hit area.

### Elevation
- **Raised (rest)**: `inset 0 1px 0 rgba(255,255,255,.12)` + `0 1px 2-3px rgba(0,0,0,.7)` + `0 0 0 .5px rgba(255,255,255,.07)`
- **Raised (pressed)**: face darkens, the top highlight flips to `inset 0 2px 3px rgba(0,0,0,.7)`, and the whole button **translates down 1 pt** — roughly 1 mm of implied travel
- **Recessed**: `inset 0 1px 2-3px rgba(0,0,0,.8-.9)` + `inset 0 0 0 .5px rgba(255,255,255,.05-.06)`

Aim for one or two millimetres of implied depth. No bevels for their own sake, no leather, no gloss.

---

## 11. Haptics & motion

| Trigger | Haptic | Motion |
| --- | --- | --- |
| detent | `.rigid` once on arrival | indicator sticks for 6 pt of travel; accent tick brightens over 120 ms |
| step | `.selection` (soft) | none |
| range limit | `.heavy` once | end wall lights; no overscroll |
| threshold crossing | `.medium` | caption crossfades 90 ms |
| stage switch | `.selection` | raised face jumps instantly; chips + control swap in **80 ms** with a 4 pt slide in the direction of light |
| parameter switch | `.light` | readout and track swap in **60 ms**; caption slot clears then fills. No spring. |
| reset (long-press / double-tap) | `.rigid` | value eases home in 160 ms; dot fades |
| stock change | `.medium` | canvas re-renders live (no fade); the strip's accent ring slides in 120 ms |
| compare engage / release | `.light` | image swaps **instantly**; pill inverts in 120 ms |
| button press | `.light` | 1 pt depress |

Detents fire at: 0 EV · the stock's own Kelvin balance · 0 tint · `box` development · 100 % on bloom, halation and grain · 0 on vignette, gate weave and frame border · the reciprocity threshold on the shutter dial.

Stage and parameter switching must feel **instant**. Never animate them slowly.

**Reduce Motion** removes animation only — haptics stay, and the reset becomes an instant snap.

---

## 12. Accessibility

- **Dynamic Type**: captions wrap to 3 lines and the readout drops to 28 pt. The deck grows by exactly one 14 pt line and **the canvas gives up the height** — the deck's bottom edge and the action row do not move. Beyond the largest accessibility size, the caption slot becomes scrollable within its own bounds rather than growing further.
- **VoiceOver**: every chip is a button with its value as the accessibility value; the scrubber is an adjustable element with ⅙-stop increments; hold-to-compare keeps its existing named action; the filmstrip is a container with `.isSelected` on the current cell.
- **Every gesture has a non-gesture equivalent**: canvas drag → the scrubber; pinch loupe → the Sheet action's long-press menu; hold-to-compare → the VoiceOver toggle action.
- **Contrast**: all body text is full-opacity ink on the deck surfaces; captions at 62 % on `#121214` clear 4.5:1.

---

## 13. Other form factors

- **Landscape / iPad**: the deck becomes a **320 pt right-hand column**. The stage selector goes vertical — top-to-bottom is still light's order — and the thumb zone is the column's lower half. The photo takes the full height. This is genuinely better in landscape than a bottom deck and should be built, not adapted.
- **Light mode**: paper `#F4F2EE` for deck and sheets, ink `#141414`, same accent. **The canvas surround stays `#050505`** — the photo always sits on black, in every mode. (Not yet mocked.)

---

## 14. Non-goals

No onboarding, no gamification, no "AI enhance", no social, no stock-photo imagery, no gradients-as-personality, **no long scrolling forms**. If a decorative element cannot be justified by what the render pipeline actually does, cut it. The grease-pencil circle on the contact sheet is the single decorative element in the app and it marks the loaded stock.

---

## 15. Not yet designed
- Large-text (Dynamic Type) mock
- Light-mode pass
- Landscape / iPad layout beyond the description in §13

## Assets
- `assets/reference.png` — **synthetic placeholder photograph**, generated for the mocks. Not a product asset. Replace with a real frame or ignore.
- No icons are final: the small glyphs in the action row are placeholders. Use SF Symbols in the implementation.

## Files
- `Dye Editor.dc.html` — all 17 screens (`1a`–`1q`). Open in a browser.
- `ios-frame.jsx` — device bezel used by the mock only. Not part of the design.
- `github.md` — the source-repo association and screen→source map.

## Source of truth
Behaviour, ranges and caption copy come from `guillermo-rebolledo/dye@main`:
`FilmApp/EditorModel.swift` · `FilmApp/FilmApp.swift` · `FilmApp/ExportSheet.swift` · `FilmApp/PresetSheet.swift` · `FilmApp/ContactSheetView.swift` · `Curves/*/stock.json`.
Where this document and the engine disagree, the engine wins.
