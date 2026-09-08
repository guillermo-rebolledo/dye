import Foundation
import FilmEngine

enum StepWedgeStage: String {
    case density
    case measuredDensity = "measured-density"
    case scanOutput = "scan-output"
    case reversalOutput = "reversal-output"
    case chromaticOutput = "chromatic-output"
    case filterFactor = "filter-factor"

    var units: String {
        switch self {
        case .density, .measuredDensity: "optical density"
        case .scanOutput, .reversalOutput, .chromaticOutput: "display-linear channel value"
        case .filterFactor: "stops of exposure"
        }
    }

    /// How far this stage may miss its reference by. Every stage but one is a density
    /// or a channel value and answers to the CLI's own tolerance. Contrast Filter
    /// factors are exposure ratios published rounded to 1.5, 2, 2.5, 6 and 8 — a third
    /// of a stop of quantisation before the model is even wrong — and are compared
    /// against an artistic transmittance rather than a digitised measurement, so they
    /// carry their own bound. It is loose enough to pass and tight enough to catch a
    /// Contrast Filter applied as a tint, dropped, or read off the wrong Stock.
    static let filterFactorStops = 0.7

    func tolerance(default value: Double) -> Double {
        self == .filterFactor ? Self.filterFactorStops : value
    }
}

struct StepWedgeRow {
    var stage: StepWedgeStage = .density
    let developmentOffset: Double
    let channel: Int
    let logExposure: Double
    let reference: Double
    let rendered: Double
    var error: Double { abs(reference - rendered) }
}

/// A Step Wedge measures the Film Response, so the passes around it are neutralised.
/// The Scene Illuminant is the balance of the Profile being rendered — the Stock's
/// own for a shipped Profile, and the identity balance for the Baker's diagnostic
/// cube — which makes White Balance an exact pass-through even on a tungsten Stock.
/// Bloom, Halation and Grain are off, because neighbouring wedge samples are
/// unrelated exposures rather than adjacent points in one scene, and a Step Wedge
/// measures the curve rather than the fluctuation around it. The push rating and the
/// True Speed rating are both cancelled by an equal exposure, so each variant is
/// probed at the CSV's own physical log exposure rather than at the one a meter
/// would have chosen.
func wedgeSettings(balancedFor profile: Profile, offset: Double = 0, outputStage: OutputStage? = nil) -> RenderSettings {
    let rating = log2(profile.metadata.nominalISO / profile.metadata.trueISO)
    return RenderSettings(output: .workingSpace, temperatureKelvin: profile.metadata.balance, exposureStops: offset - rating,
                          developmentOffset: offset, halationIntensity: 0, bloomIntensity: 0, grainIntensity: 0, outputStage: outputStage)
}

/// Composes the Baker/codec and renderer seams; no individual pass is exposed.
func stepWedge(curves: CurveSet, profile: Profile) async throws -> [StepWedgeRow] {
    guard profile.id == curves.metadata.id, profile.metadata == (try curves.bakedMetadata) else {
        throw FilmError.invalid("Profile metadata does not match the reference Curve Set")
    }
    if curves.metadata.colour.inputShaper != nil {
        return curves.metadata.process.isMonochrome
            ? try await monochromeStepWedge(curves: curves, profile: profile)
            : try await spectralStepWedge(curves: curves, profile: profile)
    }
    let variants: [(Double, String)] = curves.metadata.monochrome.map { [(0, $0.densityCurve)] }
        ?? curves.metadata.colour.lutVariants.map { ($0.pushStops, $0.lut) }
    let renderer = try Renderer()
    var rows: [StepWedgeRow] = []
    for (offset, payload) in variants {
        let channels = try curves.characteristicCurves(for: payload)
        for (channel, curve) in channels.enumerated() {
            // Include digitised points and between-point probes to catch LUT resolution errors.
            var samples = curve.points.map { ($0.logExposure, $0.density) }
            for (a, b) in zip(curve.points, curve.points.dropFirst()) {
                samples.append(((a.logExposure + b.logExposure) / 2, (a.density + b.density) / 2))
            }
            samples.sort { $0.0 < $1.0 }
            // The collapse's weights are normalised, so a neutral of this linear value
            // reaches the Density Curve at exactly this log exposure.
            let pixels = samples.flatMap { x, _ -> [Float16] in
                let exposure = Float16(pow(10, x))
                return [exposure, exposure, exposure, 1]
            }
            let image = try LinearImage(width: samples.count, height: 1, rgba: pixels)
            // Read Density Space before the runtime scan inverts it.
            let rendered = try await renderer.render(image: .linear(image), profile: profile,
                settings: wedgeSettings(balancedFor: profile, offset: offset, outputStage: OutputStage.none))
            for (index, sample) in samples.enumerated() {
                rows.append(StepWedgeRow(developmentOffset: offset, channel: channel, logExposure: sample.0,
                    reference: sample.1, rendered: Double(rendered.rgba[index * 4 + channel])))
            }
        }
    }
    return rows
}

func writeStepWedge(_ rows: [StepWedgeRow], prefix: URL) throws {
    var csv = "stage,developmentOffset,channel,logExposure,reference,rendered,absoluteError\n"
    for row in rows { csv += "\(row.stage.rawValue),\(row.developmentOffset),\(row.channel),\(row.logExposure),\(row.reference),\(row.rendered),\(row.error)\n" }
    try csv.write(to: prefix.appendingPathExtension("csv"), atomically: true, encoding: .utf8)
    let stages = Set(rows.map(\.stage)).sorted { $0.rawValue < $1.rawValue }
    let height = max(1, stages.count) * 400
    var svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="800" height="\(height)" viewBox="0 0 800 \(height)">
    <rect width="800" height="\(height)" fill="white"/>
    """
    for (panel, stage) in stages.enumerated() {
        let selected = rows.filter { $0.stage == stage }
        let minX = selected.map(\.logExposure).min() ?? -1
        let maxX = selected.map(\.logExposure).max() ?? 0
        let maxY = max(selected.map { max($0.reference, $0.rendered) }.max() ?? 1, 0.001)
        let units = stage.units
        func point(_ row: StepWedgeRow, reference: Bool) -> (Double, Double) {
            let x = 60 + 690 * (row.logExposure - minX) / max(maxX - minX, 0.001)
            let y = 340 - 300 * (reference ? row.reference : row.rendered) / maxY
            return (x, y)
        }
        svg += """
        <g transform="translate(0,\(panel * 400))">
        <g font-family="sans-serif" font-size="12" fill="#222">
        <text x="60" y="20">\(stage.rawValue): reference solid/filled; rendered dashed/open; RGB channel colours</text>
        <text x="250" y="390">log10 exposure (\(minX) to \(maxX))</text>
        <text x="60" y="365">\(units): 0 to \(maxY); max error: \(selected.map(\.error).max() ?? 0)</text>
        <text x="60" y="380">Development Offsets: \(Set(selected.map(\.developmentOffset)).sorted().map { String($0) }.joined(separator: ", "))</text>
        </g><path d="M60 35 V340 H750" fill="none" stroke="#555"/>
        """
        for offset in Set(selected.map(\.developmentOffset)).sorted() {
            for channel in 0..<3 {
                let curve = selected.filter { $0.developmentOffset == offset && $0.channel == channel }.sorted { $0.logExposure < $1.logExposure }
                guard !curve.isEmpty else { continue }
                let colour = ["#b52222", "#18762b", "#2256bb"][channel]
                for reference in [true, false] {
                    if stage == .chromaticOutput {
                        for row in curve {
                            let (x, y) = point(row, reference: reference)
                            svg += "<circle cx=\"\(x)\" cy=\"\(y)\" r=\"\(reference ? 2 : 4)\" fill=\"\(reference ? colour : "none")\" stroke=\"\(colour)\"/>"
                        }
                    } else {
                        let points = curve.map { row in let (x, y) = point(row, reference: reference); return "\(x),\(y)" }.joined(separator: " ")
                        let dash = reference ? "" : " stroke-dasharray=\"5 4\""
                        svg += "<polyline points=\"\(points)\" fill=\"none\" stroke=\"\(colour)\"\(dash)/>"
                    }
                }
            }
        }
        svg += "</g>"
    }
    svg += "</svg>\n"
    try svg.write(to: prefix.appendingPathExtension("svg"), atomically: true, encoding: .utf8)
}
