import FilmEngine

/// The complete editable look, including adjustments temporarily switched off.
struct EditorLookSnapshot {
    let stockID: String
    let settings: RenderSettings
    let stashedAdjustments: [Parameter.Identity: Double]
}
