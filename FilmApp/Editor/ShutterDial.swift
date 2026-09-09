import SwiftUI

/// Shutter speed shares the parameter dial's interaction, in thirds of a stop.
struct ShutterDial: View {
    let parameter: Parameter
    var isEnabled = true

    var body: some View {
        ParameterDial(parameter: parameter, isEnabled: isEnabled)
    }
}

private struct ShutterPreview: View {
    @State private var stops = 0.0
    var body: some View {
        ShutterDial(parameter: Parameter(id: .exposureTime, name: "Exposure time", stage: .light,
            value: $stops, range: EditorRange.exposureTimeStops, step: 1 / 3, detent: 0,
            control: .shutterDial, format: { Parameter.shutterSpeed(pow(2, $0)) }))
            .padding(.horizontal, Tokens.Metrics.space16).background(Tokens.Palette.deck)
    }
}

#Preview("Shutter dial · reciprocity threshold at 1 s") { ShutterPreview().preferredColorScheme(.dark) }
