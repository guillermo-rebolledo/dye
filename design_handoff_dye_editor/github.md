repo: guillermo-rebolledo/dye
branch: main
path: FilmApp

## Last sync
date: 2026-09-08T16:46:23Z

### Updated in this project
- Read FilmApp/FilmApp.swift, EditorModel.swift, ExportSheet.swift for control ranges, captions, conditional visibility
- Read Curves/portra-400 and cinestill-800t stock.json for balance, halation, derivedFrom
- Editor redesigned as fixed control deck (not a rebuild of the repo's scrolling stage cards)

## Screen map
| Screen | Repo files |
| --- | --- |
| Editor (all states) | FilmApp/FilmApp.swift, FilmApp/EditorModel.swift, FilmApp/FilmCanvas.swift |
| Export sheet states | FilmApp/ExportSheet.swift, FilmApp/EditorModel.swift |
| Presets | FilmApp/PresetSheet.swift |
| Contact sheet | FilmApp/ContactSheetView.swift, Sources/FilmEngine/ContactSheetReference.swift |
| Stock filmstrip | Curves/*/stock.json |
