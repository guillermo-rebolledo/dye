import Foundation
import FilmEngine

struct CharacteristicCurve {
    struct Point { let logExposure: Double; let density: Double }
    let points: [Point]

    init(url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: .newlines).enumerated().filter {
            let line = $0.element.trimmingCharacters(in: .whitespaces)
            return !line.isEmpty && !line.hasPrefix("#")
        }
        guard lines.first?.element.trimmingCharacters(in: .whitespaces) == "logExposure,density" else {
            throw FilmError.invalid("\(url.lastPathComponent): expected logExposure,density header")
        }
        var points: [Point] = []
        for (line, text) in lines.dropFirst() {
            let fields = text.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count == 2, let x = Double(fields[0]), let y = Double(fields[1]),
                  x.isFinite, y.isFinite, x <= 0, x >= log10(Double(Float16.leastNonzeroMagnitude)),
                  y >= 0, y <= Double(Float16.greatestFiniteMagnitude),
                  points.last.map({ x > $0.logExposure }) ?? true else {
                throw FilmError.invalid("\(url.lastPathComponent):\(line + 1): expected increasing finite log exposure and nonnegative finite density")
            }
            points.append(Point(logExposure: x, density: y))
        }
        guard points.count >= 2 else { throw FilmError.invalid("\(url.lastPathComponent): at least two samples required") }
        self.points = points
    }

    func density(atLinearExposure exposure: Double) -> Double {
        let x = log10(max(exposure, Double.leastNormalMagnitude))
        if x <= points[0].logExposure { return points[0].density }
        for (a, b) in zip(points, points.dropFirst()) where x <= b.logExposure {
            let weight = (x - a.logExposure) / (b.logExposure - a.logExposure)
            return a.density + weight * (b.density - a.density)
        }
        return points[points.count - 1].density
    }
}

struct CurveSet {
    let metadata: FilmProfile
    let directory: URL
    init(directory: URL) throws {
        self.directory = directory
        metadata = try JSONDecoder().decode(FilmProfile.self, from: Data(contentsOf: directory.appendingPathComponent("stock.json")))
        try metadata.validate()
        guard metadata.colour.lutSize == 33 else { throw FilmError.invalid("The Baker emits 33³ Colour Cubes") }
    }

    func characteristicCurves(for payload: String) throws -> [CharacteristicCurve] {
        // Payload references are container names, never paths outside the Curve Set.
        guard !payload.isEmpty, !payload.contains("/"), !payload.contains("\\"), payload != ".", payload != ".." else {
            throw FilmError.invalid("Payload names must be plain filenames")
        }
        let stem = (payload as NSString).deletingPathExtension
        let names = metadata.process.isMonochrome ? [stem + ".csv"] : ["red", "green", "blue"].map { stem + "." + $0 + ".csv" }
        return try names.map { try CharacteristicCurve(url: directory.appendingPathComponent($0)) }
    }
}
