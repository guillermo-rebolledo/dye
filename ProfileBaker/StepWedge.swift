import Foundation
import FilmEngine

struct StepWedgeRow {
    let developmentOffset: Double
    let channel: Int
    let logExposure: Double
    let reference: Double
    let rendered: Double
    var error: Double { abs(reference - rendered) }
}

/// Composes the Baker/codec and renderer seams; no individual pass is exposed.
func stepWedge(curves: CurveSet, profile: Profile) async throws -> [StepWedgeRow] {
    guard profile.id == curves.metadata.id, profile.metadata == curves.metadata else {
        throw FilmError.invalid("Profile metadata does not match the reference Curve Set")
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
            let weightSum = curves.metadata.monochrome?.spectralWeight.reduce(0, +) ?? 1
            let pixels = samples.flatMap { x, _ -> [Float16] in
                let exposure = Float16(pow(10, x) / weightSum)
                return [exposure, exposure, exposure, 1]
            }
            let image = try LinearImage(width: samples.count, height: 1, rgba: pixels)
            let rendered = try await renderer.render(image: .linear(image), profile: profile,
                settings: .init(output: .workingSpace, developmentOffset: offset))
            for (index, sample) in samples.enumerated() {
                rows.append(StepWedgeRow(developmentOffset: offset, channel: channel, logExposure: sample.0,
                    reference: sample.1, rendered: Double(rendered.rgba[index * 4 + channel])))
            }
        }
    }
    return rows
}

func writeStepWedge(_ rows: [StepWedgeRow], prefix: URL) throws {
    var csv = "developmentOffset,channel,logExposure,referenceDensity,renderedDensity,absoluteError\n"
    for row in rows { csv += "\(row.developmentOffset),\(row.channel),\(row.logExposure),\(row.reference),\(row.rendered),\(row.error)\n" }
    try csv.write(to: prefix.appendingPathExtension("csv"), atomically: true, encoding: .utf8)
    let minX = rows.map(\.logExposure).min() ?? -1
    let maxX = rows.map(\.logExposure).max() ?? 0
    let maxY = max(rows.map { max($0.reference, $0.rendered) }.max() ?? 1, 0.001)
    func point(_ row: StepWedgeRow, reference: Bool) -> String {
        let x = 60 + 690 * (row.logExposure - minX) / max(maxX - minX, 0.001)
        let y = 340 - 300 * (reference ? row.reference : row.rendered) / maxY
        return "\(x),\(y)"
    }
    var svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="800" height="400" viewBox="0 0 800 400">
    <rect width="800" height="400" fill="white"/>
    <g font-family="sans-serif" font-size="12" fill="#222">
    <text x="60" y="20">Step Wedge — reference (solid) / rendered (dashed)</text>
    <text x="330" y="390">log10 exposure (\(minX) to \(maxX))</text>
    <text x="60" y="365">Density: 0 to \(maxY); max absolute error: \(rows.map(\.error).max() ?? 0)</text>
    </g><path d="M60 35 V340 H750" fill="none" stroke="#555"/>
    """
    for offset in Set(rows.map(\.developmentOffset)).sorted() {
        for channel in 0..<3 {
            let selected = rows.filter { $0.developmentOffset == offset && $0.channel == channel }
            guard !selected.isEmpty else { continue }
            let colour = ["#b52222", "#18762b", "#2256bb"][channel]
            for reference in [true, false] {
                let points = selected.map { point($0, reference: reference) }.joined(separator: " ")
                let dash = reference ? "" : " stroke-dasharray=\"5 4\""
                svg += "<polyline points=\"\(points)\" fill=\"none\" stroke=\"\(colour)\"\(dash)/>"
            }
        }
    }
    svg += "</svg>\n"
    try svg.write(to: prefix.appendingPathExtension("svg"), atomically: true, encoding: .utf8)
}
