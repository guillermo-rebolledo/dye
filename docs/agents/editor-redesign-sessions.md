# Agent sessions: the editor redesign

Shared protocol for the sessions that implement `docs/editor-redesign.md`. Every
ticket under MEM-254 assumes this file has been read and does not repeat it.

## Read before writing anything

1. `CONTEXT.md` — the project's canonical glossary. It is not optional reading.
   When you name a domain concept in a type, a comment or a commit message, use
   the term defined there. Several terms exist specifically to break a collision:
   `balance`, `curve`, `LUT`, `seam` and `development` each meant two or three
   things before, so `Stock Balance` and `White Balance` are always qualified and
   bare `balance` is never used.
2. `docs/editor-redesign.md` — the implementation spec. §2 lists six places where
   the design handoff and the engine disagree, all already resolved.
3. `design_handoff_dye_editor/README.md` — appearance, and the numbers behind it.
   Open `Dye Editor.dc.html` in a browser for the screens it references by id.
4. Your ticket.

## The rule that decides every disagreement

**The handoff is the source of truth for appearance. The engine is the source of
truth for behaviour.** The handoff's own README says so, and §2 of the spec has
already applied it. Do not re-derive those six resolutions and do not "fix" them
back toward the handoff:

- Vignette, Gate weave and Frame border are **0–100 %**. The handoff says 0–200 %
  and is wrong; the engine ranges are `0.0...1.0`.
- Bloom, Halation and Grain **are** 0–200 %, detent at 100 %.
- Exposure at ±3 EV and Temperature at 2000–10000 K are deliberate **UI clamps**
  inside wider engine ranges. Keep them, name them, and never reject a Preset
  value that falls outside one.
- The filmstrip shows **every** Catalogue entry, study Profiles included, in the
  order `ProfileCatalogue.bundled()` returns. Never hardcode a cell count.
- The contrast-filter readout shows the stop cost **unsigned**.
- The Lab sub-label keeps `Display P3` for the Identity Profile.

If you believe one of these is wrong, say so in the pull request. Do not change it
silently.

## Scope guardrails

**This is a presentation-layer change.** Unless your ticket explicitly says
otherwise:

- Do not modify anything under `Sources/FilmEngine/`. Four tickets add reporting
  fields to `FilmApp/EditorModel.swift`; none of them touch a shader, a Pass or a
  render path.
- Never edit `Sources/FilmEngine/Catalogue/*.filmprofile` or `Curves/`. CI bakes
  the Catalogue and fails on any byte difference.
- Add no third-party dependencies. `Package.swift` stays as it is.
- SwiftUI, iOS 17+. The brief forbids non-Apple rendering stacks, and forbids
  stock UIKit controls for the scrubber specifically.
- Take every colour, size, radius and shadow from the design tokens. If a value
  you need is not there, add it to the token file rather than inlining a literal.

## Files, and who owns them

Every file below is pre-registered in `FilmApp.xcodeproj` by the Redesign 0
session, so no later session edits `project.pbxproj`. **Create no new files
outside this map without saying so in the pull request.**

| File | Owned by |
| --- | --- |
| `FilmApp/Design/Tokens.swift` | Redesign 1 |
| `FilmApp/Design/Surfaces.swift` | Redesign 1 |
| `FilmApp/Design/Haptics.swift` | Redesign 1 |
| `FilmApp/Editor/Parameter.swift` | Redesign 2 |
| `FilmApp/Editor/EditorSelection.swift` | Redesign 2 |
| `FilmApp/Editor/Scrubber.swift` | Redesign 3 |
| `FilmApp/Editor/DeckView.swift` | Redesign 4 |
| `FilmApp/Editor/StageSelector.swift` | Redesign 4 |
| `FilmApp/Editor/ActionRow.swift` | Redesign 4 |
| `FilmApp/Editor/ParameterRow.swift` | Redesign 4a |
| `FilmApp/Editor/ActiveControl.swift` | Redesign 4b |
| `FilmApp/Editor/ContrastFilterDiscs.swift` | Redesign 4c |
| `FilmApp/Editor/OutputStageCards.swift` | Redesign 4c |
| `FilmApp/Editor/ShutterDial.swift` | Redesign 4c |
| `FilmApp/Editor/CanvasView.swift` | Redesign 5 |
| `FilmApp/Editor/EditorView.swift` | Redesign 5 |
| `FilmApp/Editor/Filmstrip.swift` | Redesign 6 |
| `FilmApp/FilmCanvas.swift` | Redesign 7 (loupe only) |
| `FilmApp/EditorModel.swift` | Redesign 8a, 8b, 8c — additive only |
| `FilmApp/ExportSheet.swift` | Redesign 8a |
| `FilmApp/PresetSheet.swift` | Redesign 8b |
| `FilmApp/ContactSheetView.swift` | Redesign 8c |
| `FilmApp/FilmApp.swift` | Redesign 5 — shrinks to the `App` entry point |

`FilmApp/EditorModel.swift` is touched by three sessions. Each adds a distinct
member and none rewrites an existing one, so run those three sequentially rather
than concurrently if you can.

## Running sessions side by side

Redesign 1, 2 and 8a/8b/8c touch disjoint files and can run at the same time.
Everything else sits on the critical path: 3 needs 1, 4 needs 2 and 3, the rest
need 4. The Linear issues carry these as blocking relations, so the backlog shows
what is startable.

## Verifying

There is **no test target for `FilmApp`**. `Tests/FilmEngineTests` covers the
engine only, so a UI ticket cannot be verified by running tests, and adding a UI
test target is not part of this work. What you must do instead:

```
swift build
xcodebuild -project FilmApp.xcodeproj -scheme FilmApp \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO build
```

Run `swift test` as well if you touched anything under `Sources/`.

**Every component you build gets a `#Preview`**, and that preview is the
deliverable's evidence. Cover the states your ticket lists — a scrubber preview
shows rest, mid-drag, at-detent and at-limit; a deck preview shows Tri-X, Velvia,
Portra and Identity. A ticket whose states cannot be seen in a preview is not
finished.

## Committing

Branch names come from the Linear issue's own `gitBranchName`, e.g.
`gortizdev/mem-255-redesign-1-design-tokens-and-control-primitives`.

Commit subjects match the existing history: `MEM-255: <what changed>`. Open a pull
request against `main` when the build is green.

Leave `docs/editor-redesign.md` alone unless your ticket changes a decision in it,
in which case update the spec in the same pull request.
