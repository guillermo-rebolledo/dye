# Dye — "one rail" redesign spec

A delta spec against the shipped editor at `guillermo-rebolledo/dye@main` (read 2026-09-10). It describes only what changes. Anything not mentioned here — the engine, the twelve passes, parameter ranges, captions, `EditorModel`, the sheets — is unchanged.

Design reference: [`Dye Editor - one rail.html`](Dye%20Editor%20-%20one%20rail.html), the standalone offline bundle in this folder (screens `3a`–`3d`; `3a` is interactive). It is the only design file in the repo. The earlier explorations this document refers to as "the archive" — the fixed-deck editor and the simplification passes, ids `1a`–`2f` — are not checked in; [`../docs/editor-redesign.md`](../docs/editor-redesign.md) is the record of what was built from them.

---

## 1. What changes, in one table

| Area | Shipped now | After |
| --- | --- | --- |
| Stage navigation | `StageSelector` — 4 segments + 3 chevrons in a 36 pt trough | **Deleted.** Stages become groups inside the rail |
| Parameter selection | `ParameterRow` — chips, `ViewThatFits` ladder, persistent stock + output slots | **Deleted.** Replaced by the rail |
| Active control | `ActiveControl` — header row (name + OFF tag), readout, dial | Header row **deleted**; readout and name move to the rail's own layout |
| Value control | `ParameterDial` — graduated tape, fixed centre hairline | **Unchanged mechanism**, restyled and repositioned |
| Tick labels | Major ticks labelled with value **and unit** (`−3.0 EV`, ×7) | **Deleted.** Tape carries ticks only; the readout states the unit once |
| Actions | `ActionRow` — 4 flat icon buttons on the deck | **Liquid Glass floating capsule bar** |
| Compare pill | Capsule present at rest (empty after captions were removed) | **Absent at rest**; a glass `ORIGINAL` label appears only while held |
| Render time | Permanent pill | Visible during drag only, then fades |
| Deck height | 316 pt (+ dynamic-type extra) | **262 pt**, fixed, same swap-contents rule |
| Top chrome | Settings gear, `.ultraThinMaterial` circle | Same position, same material family as the bar |

Net effect: two rows of chrome (stage selector + parameter row) collapse into one rail; the deck loses 54 pt, which returns to the canvas.

---

## 2. The rail

### 2.1 Model

One ordered list of every parameter across all four stages, in **pipeline order** — Light → Film → Lab → Adjust. Order is a correctness property of the engine and it is now expressed as the rail's own left-to-right axis. Do not sort, group alphabetically, or let the user reorder.

Build it from `EditorStage.allCases.flatMap { model.parameters(for: $0) }`. Group boundaries are where `parameter.stage` changes.

| Group | Members | Count |
| --- | --- | --- |
| LIGHT | Exposure · Temperature · Tint · Exposure time¹ | 3–4 |
| FILM | Stock² · Contrast filter³ · Development · Bloom · Halation · Grain | 4–6 |
| LAB | Scan/Print⁴ · Vignette · Gate weave · Frame border | 0–4 |
| ADJUST | Brilliance · Highlights · Shadows · Contrast · Brightness · Black point · Saturation · Vibrance | 8 |

¹ only when `model.hasReciprocity` · ² a mode, not a value · ³ only when `!model.contrastFilters.isEmpty` · ⁴ only when `model.outputStages` is non-empty

Rail length is 15–22 pucks. **An unavailable parameter is absent, not disabled** — there is no dimmed puck state. A reversal stock's rail is visibly shorter because it has no LAB group, and that is the intended signal.

### 2.2 Geometry

```
group label        10 pt caps mono, tracking .14em, 42% ink
readout            32/34 pt mono, tabular  +  14 pt unit
rail               72 pt band · pucks 56 pt · selected 64 pt · pitch 76 pt
parameter name     11 pt SF Pro, 75% ink, centred
tape               20 pt · 9 pt per step · major every 54 pt (6 steps)
glass bar          58 pt capsule, inset 16 pt, 12 pt above home indicator
──────────────────────────────────────────────────────────────────────
deck               262 pt total, fixed
```

Centre line is at 196.5 pt (half of 393). 5½ pucks visible, so the group boundary you are approaching is always on screen before you reach it.

Group separator between groups: a 0.5 pt × 30 pt hairline at 16% white with the **next** group's name beneath it in 8 pt caps mono at 30% ink, in a 26 pt wide slot. It reads before you arrive.

### 2.3 Puck states

| State | Treatment |
| --- | --- |
| default | 56 pt circle, `radial-gradient(#232327 → #171719)`, `inset 0 1px 0 rgba(255,255,255,.10)`, `0 2px 5px rgba(0,0,0,.6)`, `0 0 0 .5px rgba(255,255,255,.08)` |
| modified | as default + 5 pt accent dot at upper right (inset 7 pt) |
| selected | 64 pt (scale 1.143), `radial-gradient(#2A2A2F → #1B1B1F)`, `inset 0 1px 0 rgba(255,255,255,.16)`, `0 2px 6px rgba(0,0,0,.7)`, **`0 0 0 2px accent`**, `0 0 0 5px #0B0B0C` |
| pressed | scale 0.94, mark to 60% — glass and pucks light rather than travel |
| rendering | hatched `#141416`/`#17171A` — **Stock puck only**, while a thumbnail renders |

Transitions: `transform` and `box-shadow` 90 ms ease-out. There is no unavailable state.

### 2.4 Marks

Geometric, built from circles, halves and gradients — the densitometer and step-wedge vocabulary, not illustration. 24 pt, 26 pt when selected.

| Parameter | Mark |
| --- | --- |
| Exposure | disc split 50/50 black · paper, 1.5 pt inner ring |
| Temperature | horizontal sweep `#4E7FC6 → #D9A45A` |
| Tint | horizontal sweep `#4E9A4A → #B45AA8` |
| Stock | **live thumbnail** of the user's photo through that stock, circular, with a 3 pt process-coloured bottom edge |
| Development | three ascending bars |
| Bloom | white radial glow |
| Halation | warm radial glow (`rgba(255,190,140)` core) |
| Grain | dot field, 6 pt lattice |
| Scan / Print | disc split on the 135° diagonal |
| Vignette | radial, light core → `#1B1B1F` edge |
| Gate weave | vertical bar pairs |
| Frame border | 2.5 pt square ring, hollow |
| Adjust (8) | tonal and chroma gradients — **placeholders; use SF Symbols in the build** |

The glass bar's four glyphs are also placeholders: `photo` · `slider.horizontal.3` · `square.grid.3x3` · `square.and.arrow.up`.

---

## 3. Gestures

Two horizontal gestures, **stacked and never overlapping**, 12 pt apart.

| Target | Gesture | Behaviour |
| --- | --- | --- |
| Rail (72 pt band) | horizontal drag | Selects. Paged scroll, one puck per page — **it cannot rest between pucks**. 76 pt of travel per puck. A flick decelerates across several; each one clicks |
| Rail puck | tap | Jumps directly to that puck |
| Tape (44 pt hit band) | horizontal drag | Adjusts. 9 pt per step, from anywhere in the width |
| Parameter name | long-press / double-tap | Resets to default |
| Group label | tap | Four-item jump menu (Light · Film · Lab · Adjust) → that group's first puck |
| Canvas | long-press ≥150 ms | Hold to compare (unchanged) |
| Canvas | horizontal drag | Fine adjust of the active parameter at half gain (unchanged) |
| Canvas | pinch | 1:1 loupe (unchanged) |

The old "draggable from anywhere in the deck's width" rule now means **anywhere in the tape's 44 pt band** — the rail owns the band above it.

**The group jump menu is not optional.** Merging the stages costs the one-tap stage switch the old selector gave for free; the menu is what buys it back.

---

## 4. Numeric readout

```swift
Text(parts.number)
    .font(.system(size: 32, weight: .medium, design: .monospaced))
    .monospacedDigit()
    .frame(width: Tokens.Deck.readoutNumberWidth, alignment: .center)
    .contentTransition(reduceMotion ? .identity : .numericText(value: value))
```

- **Pass the value.** `.numericText()` with no argument always rolls upward; with `value:` SwiftUI rolls in the direction the number actually moved.
- Wrap value changes in `withAnimation(.snappy(duration: 0.12))`. Slower and the number lands after the picture, which reads as render lag.
- `.monospacedDigit()` **plus** a fixed-width frame. A rolling digit must not change the readout's width mid-drag.
- The sign belongs to the format (`%+.1f`) so it holds its column across zero.
- **Unit and group label are plain text** — they swap, never roll. A rolling `%` looks like it means something.
- Non-numeric readouts (`box` / `push +1`, `Scan` / `Print`, the stock name) render as plain text at 22 pt, no transition.

State is carried by the mark and the unit, not by words — the `● DETENT` and `OFF` tags are gone:

| Condition | Signal |
| --- | --- |
| at a detent | hairline 2 → 3 pt, height 20 → 24 pt, bloom `0 0 14px accent`, **unit turns accent** |
| off default | accent dot on the puck |
| mid-drag | tape ink .24 → .34, majors .45 → .60 |
| zero on a geometry control | readout in quiet ink, unit accent |

---

## 5. Liquid Glass action bar

```swift
HStack { … }
    .glassEffect(.regular, in: .capsule)
```

Wrap the bar in a `.glassEffectContainer` so the selected lens **morphs** between items instead of cross-fading. Do not hand-roll it from `.ultraThinMaterial` + a stroke — the real material carries the specular edge and the adaptive tint.

- Floating capsule, 58 pt tall, inset 16 pt from screen edges, 12 pt above the home indicator. Radius is half the height — fully concentric, never a rounded rectangle.
- Selected: a brighter glass lens, 52 × 40, capsule, **inside** the bar's material. **Never accent-filled** — accent means "the film's own value", and a tab is not a value.
- Four icons, no labels. Names live in the accessibility labels and the long-press menu.
- Pressed: lens scales to 0.94 and the glass brightens. **No vertical travel** — the 1 pt depress belonged to the old opaque faces.
- Disabled: icon to 30%. The bar's material never dims; a dim bar reads as a dimmed app.
- Settings stays a 34 pt circle of the same material, top-right. It earns the only top chrome by being rare — putting it in the bar would spend a quarter of the thumb zone on a screen opened twice.
- Reduce Transparency: `#1C1C20` with a hairline, same geometry, no blur. Increase Contrast adds a 1 pt edge.

---

## 6. Haptics and motion

| Trigger | Haptic | Motion |
| --- | --- | --- |
| puck lands | `.selection` | readout, name, tape swap in 60 ms |
| group boundary crossed | `.medium` (heavier than the per-puck click) | group label crossfades 90 ms |
| tape step | `.selection` soft | none |
| detent | `.rigid` | hairline widens and blooms 110 ms; tape sticks for 6 pt |
| range limit | `.heavy` | end wall lights; no rubber-band |
| threshold crossing (reciprocity, stock balance) | `.medium` | — |
| reset | `.rigid` | value rolls home in 160 ms |
| stock change | `.medium` | canvas re-renders live, no fade; accent ring slides 120 ms |
| compare engage / release | `.light` | image swaps **instantly**; label fades 120 ms |
| button press | `.light` | glass brightens, lens scales 0.94 |

Rail settle is 220 ms `cubic-bezier(.22,.8,.28,1)`; during a drag the transition is 0 ms so the rail tracks the finger. Reduce Motion removes animation only — **haptics stay**, and reset becomes an instant snap.

---

## 7. Takeover surfaces

Two pucks are modes whose control is not a dial. Centring one **replaces the rail and tape** within the same 262 pt frame; nothing else moves.

- **Stock** (`3c`) — the filmstrip: full-bleed 104 pt strip, `#141416`, sprocket rebates top and bottom, 96 × 60 cells with process-coloured bottom edge and frame number, process legend beneath. The readout row becomes the stock's name. Swiping the strip past its last cell hands control back to the rail at the next puck, so one continuous horizontal gesture still walks the whole pipeline.
- **Scan / Print** — the two-card treatment (a card per picture, selected card ringed in accent). Reference is `1f` in the archive document.

---

## 8. Accessibility

- The rail is one **adjustable** element: swipe up/down moves puck to puck. Each puck is a button with the parameter's name as its label and `parameter.readout` as its value. `.isSelected` on the centred puck.
- The group is announced on entry into it.
- Dynamic Type: readout drops to 28 pt, the parameter name and group label grow, the rail keeps its 64 pt geometry. The deck grows by exactly one line and **the canvas gives up the height** — the bar and the deck's bottom edge do not move.
- Every gesture keeps a non-gesture equivalent: rail drag → tap a puck; tape drag → VoiceOver adjustable; canvas drag → the tape; pinch loupe → the long-press menu; hold-to-compare → its existing named action.
- Contrast: all body text is full-opacity ink on `#0B0B0C`. The group label at 42% is decorative — never the only carrier of a value.

---

## 9. Tokens

Unchanged from the shipped palette except as noted.

| Token | Value | Note |
| --- | --- | --- |
| canvas | `#050505` | unchanged; the photo sits on black in every mode |
| deck | `#0B0B0C` | **darker than the shipped `#121214`** — the deck is now mostly empty space and the rail needs the contrast |
| puck rest | `radial-gradient(#232327 → #171719)` | new |
| puck selected | `radial-gradient(#2A2A2F → #1B1B1F)` | new |
| accent | `oklch(0.74 0.15 55)` | unchanged. Film-base orange: the colour of an unexposed C-41 mask, so it reads as "the film's own value" |
| ink | `#F2F0EC` | unchanged |
| glass fill | `rgba(255,255,255,.09)` | fallback only — prefer `.glassEffect` |
| glass edge | `inset 0 1px 0 rgba(255,255,255,.32)`, `inset 0 0 0 .5px rgba(255,255,255,.14)` | fallback only |
| tape minor | `rgba(255,255,255,.24)` → `.34` dragging | |
| tape major | `rgba(255,255,255,.45)` → `.60` dragging | |

Deleted tokens: stage-selector trough and segment metrics, chip radius/padding/compact width, the `OFF` and `DETENT` tag styles, caption slot height, `Deck.headerHeight`, `Deck.headerGap`.

Type is unchanged: SF Pro for text, SF Mono with tabular figures for **every** numeric readout.

---

## 10. File-level impact

| File | Change |
| --- | --- |
| `FilmApp/Editor/StageSelector.swift` | delete |
| `FilmApp/Editor/ParameterRow.swift` | delete (`DeckFace`, `ParameterChip` go with it) |
| `FilmApp/Editor/ParameterRail.swift` | **new** — the rail, pucks, marks, paged snap, group separators |
| `FilmApp/Editor/ActiveControl.swift` | strip the header row; keep the readout (carry `.numericText` across unchanged) and the control switch |
| `FilmApp/Editor/DeckView.swift` | rewrite the stack: group label → readout → rail → name → tape → glass bar; height 316 → 262 |
| `FilmApp/Editor/ActionRow.swift` | reskin to the glass capsule; drop `DeckActionPress`'s 1 pt offset |
| `FilmApp/Editor/ParameterDial.swift` | keep the mechanism; remove the major-tick labels, restyle to 20 pt |
| `FilmApp/Editor/Filmstrip.swift` | keep; it is now a takeover of the rail's slot rather than the chip row's |
| `FilmApp/Editor/EditorSelection.swift` | selection becomes a single rail index over the flattened parameter list; `stage` derives from the selected parameter |
| `FilmApp/Design/Tokens.swift` | add the rail and glass tokens; remove the deleted ones |
| `FilmApp/Editor/CanvasView.swift` | unchanged — the compare pill's rest state is removed, the held label stays |

---

## 11. Known gaps

1. **Rail length.** 22 pucks on a colour negative is a long swipe end to end. The jump menu mitigates it; if it still feels long in the hand, the next thing to try is a wider gap at group boundaries instead of a hairline, so the groups read as separate runs.
2. **Adjust marks.** Eight tonal gradients are placeholders and the weakest part of the design — Highlights and Brightness look alike at 24 pt. Needs SF Symbols or a real pass.
3. Landscape and iPad are unaddressed for the rail. The archive's recommendation (a 320 pt side column) needs rethinking — a vertical rail reads well but loses "left to right is the order light travels".
4. Light mode is unaddressed for the rail. Canvas surround stays `#050505` regardless.
5. Contact Sheet, Export, Presets and the empty/loading/error states are unchanged from the archive document and were not re-drawn against the rail.

## 12. Reference

- [`Dye Editor - one rail.html`](Dye%20Editor%20-%20one%20rail.html) — `3a` live rail (all 20 pucks, real ranges and detents, rolling digits, live grade) · `3b` detent and mid-drag · `3c` stock takeover · `3d` mechanics and puck states. Open it in a browser; it is a design reference written in HTML, not production code, and nothing in it is meant to be ported.
- [`../docs/editor-redesign.md`](../docs/editor-redesign.md) — the implementation spec for the fixed-deck editor this one supersedes, including where its handoff and the engine disagreed and how each was resolved.

Where this document and the engine disagree, the engine wins.
