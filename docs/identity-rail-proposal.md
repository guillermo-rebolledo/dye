# Persistent Stock identity and a dial-only rail

Status: research and proposal, September 10, 2026. No application changes. Based on source inspection, not a live gesture test. “Identity component” is interpreted as Stock selection and its filmstrip, including the neutral Identity profile.

## Recommendation

Give Stock a persistent header between the photo and adjustment controls. Show the current Stock prominently, with a thumbnail, its name, its Process when applicable, and an explicit disclosure. Tap opens a Stock browser. Horizontal scrolling in the adjustment rail never opens a browser or changes its layout.

The hierarchy becomes: photograph → Stock identity → individual adjustments → utility actions. Stock stays visible in Light, Film, Lab, and Adjust instead of appearing in the group title only during Film.

Conceptual portrait layout; dimensions are starting points for prototyping:

```text
┌───────────────────────────────────────┐
│                                       │
│              PHOTOGRAPH               │
│                                       │
├───────────────────────────────────────┤
│ [frame] PORTRA 400  ⌄       [Scan ⌄]  │
│         C-41                          │  Stock header
├───────────────────────────────────────┤
│                +0.4 EV                │  Active readout
│       ○     ○     ◉     ○     ○       │  Dial rail
│            LIGHT · Exposure ⌄         │  Name + stage jump
│           ┆ ┆ ┆ ┃ ┆ ┆ ┆ ┆            │  Adjustment tape
│       Photo · Presets · … · Export     │  Existing actions
└───────────────────────────────────────┘
```

Use the app's existing dark surfaces, typography, rendered stock thumbnail, and restrained Process color. The Stock name should be the strongest persistent text; the active numeric value may remain larger. Keep Stock visually separate from Output, with separate touch targets. Show Identity explicitly when selected; it must not resemble missing data. Only show an actionable Output selector when the profile supports output choices.

## Why the current interaction breaks

- `ParameterRail.swift` selects a parameter as its centered scroll position changes.
- `DeckView.swift` replaces the rail and tape with `Filmstrip` as soon as Stock is active. This can remove the scrolling surface during navigation.
- `Filmstrip.swift` provides a Controls button and end-of-strip drag exit. That does not preserve the original rail throughout the gesture; exiting also advances selection rather than restoring the previous dial.
- Output uses another takeover. Moving Stock alone leaves the same class of interruption at Scan/Print.
- The original one-rail spec deliberately describes these takeovers. This proposal revises that interaction contract; it is not merely a gesture-threshold adjustment.

These are code-backed mechanisms, not measurements of on-device behavior.

## Alternatives

| Arrangement | Strength | Cost / limitation | Decision |
| --- | --- | --- | --- |
| Persistent Stock header above dials | Visible in every adjustment stage; clear entry into browsing; separate gesture area | Modestly reduces photo height | Recommended |
| Stock badge over the photo | Preserves deck height; stays visible | Covers image detail and competes with compare/loupe; stock metadata is harder to read | Fallback if photo area proves critical |
| Fixed Stock tile beside the rail | Always available and close to the dials | Narrows the rail and creates a dead end for swipes that begin on the tile | Avoid for this complaint |
| Permanently expanded filmstrip above the rail | Maximum stock visibility and immediate browsing | Consumes substantial photo space and creates two horizontal browsing regions | Consider only for a dedicated stock-browsing workspace |

## User journey

1. **Open a photo.** The header immediately names the current Stock. In the neutral state, use `Identity` with a plain-language secondary description such as `No stock response`. Do not automatically open a chooser on every import.
2. **Choose a Stock.** Tap the header to open a bottom sheet with the current selection centered, existing real thumbnails and names, and a visible Done button. Reuse the filmstrip's visual language. The sheet can grow for larger text or catalogue browsing; maintain a useful photo preview where space permits.
3. **Compare alternatives.** Tapping stocks updates the photo live and keeps the browser open. Selections apply immediately; Done or dismissal returns to editing with the last choice. No Cancel action implying rollback. Use explicit close controls, not horizontal overscroll, to leave browsing.
4. **Adjust.** Return to the previous active dial and rail position. The Stock header remains visible while swiping through the entire rail. Stage jumps land on an adjustment, never a modal selector.
5. **Revisit identity or output.** Stock reopens from the same location. Scan/Print opens its own explicit chooser from the header and returns to the same dial. Keep existing model behavior for stock-dependent values; do not introduce a blanket reset.

## A genuinely dial-only rail

Remove Stock and Output from the navigable rail, while retaining their domain data and pipeline positions. Navigation order and renderer execution order are separate concerns; the remaining parameters stay in pipeline order.

Contrast filter currently uses discrete discs instead of a dial. To fulfill “dials only” literally, present it as a stepped tape/dial with named filter detents and the existing filter-factor readout. It remains a Film adjustment. Do not turn categories into an apparently continuous numeric control.

Keep selection independent of browser presentation. Replace `isFilmstripOpen` being derived from `.stock` selection with explicit presentation state. Reconcile selection against the rail's eligible parameters after Stock changes: preserve the same parameter ID when available; otherwise select a predictable nearest remaining adjustment. Opening or closing a browser must not call `move(1)`.

## Space and accessibility

Prototype a 56 pt header replacing the current 20 pt group row, with stage navigation relocated beside the parameter name. That implies approximately 298 pt instead of 262 pt for the default deck, before any additional spacing required by hit-target testing. This is an estimate, not a verified fit. Preserve the existing 72 pt rail and 44 pt tape bands.

Give Stock and Output separate targets of at least 44 × 44 pt. The stage/name area needs a real nonoverlapping target, not an expanded invisible region over the rail or tape; enlarge the layout if necessary. Let long Stock names wrap at large text sizes rather than shrinking them to fit. Announce Stock name, Process and selected state; color and thumbnail cannot carry identity alone. On iPad/landscape, keep the header at the top of the existing control column and use an appropriately sized sheet/popover. Larger text may require a stacked header and a larger browser.

## Implementation and validation scope

- `DeckView.swift`: add persistent header, remove takeovers, relocate stage jump, present explicit browsers.
- `EditorSelection.swift`: navigate dial parameters independently from presentation and preserve selection through stock changes.
- `ParameterRail.swift` / `Parameter.swift`: supply eligible adjustment parameters and represent Contrast filter with named steps. Preserve engine ordering and conditional availability.
- `Filmstrip.swift`: reuse catalogue visuals and live selection, replace overscroll exit with explicit dismissal.
- `EditorView.swift` / `Tokens.swift`: coordinate browser/canvas interactions and adaptive deck sizing.
- Update the one-rail spec, selection checks, glossary/navigation copy and relevant previews to reflect the new contract.

Before accepting the design, test swipes in both directions across the old Stock and Output positions, slow drags and fast flicks, tapping visible pucks, repeated browser open/close, and Stock changes that remove the current dial. Verify that every rail gesture keeps the rail mounted and no presentation appears without an explicit tap. Check long names, largest text, VoiceOver, landscape and small phone photo area. Ask users to choose a Stock, adjust across stages, identify the active Stock, and switch back; compare interruptions, successful completion and stock discoverability with the current version. No usability results are claimed yet.

## Research

See [primary-source findings](identity-layout-research.md) for Apple interaction guidance and Adobe's profile/adjustment precedent. Those sources support separating browsing from adjustment; the particular header, dimensions and state transitions above are design recommendations for Dye, not requirements imposed by those sources.
