import Foundation
import FilmEngine
import CryptoKit

struct CharacteristicCurve {
    struct Point { let logExposure: Double; let density: Double }
    let points: [Point]

    init(url: URL, exposureRange: ClosedRange<Double> = log10(Double(Float16.leastNonzeroMagnitude))...0) throws {
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
                  x.isFinite, y.isFinite, exposureRange.contains(x),
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
        guard metadata.colour.sourceFingerprint == nil else {
            throw FilmError.invalid("Source fingerprints are derived by the Baker, not authored in stock.json")
        }
        guard metadata.colour.lutSize == 33 else { throw FilmError.invalid("The Baker emits 33³ Colour Cubes") }
    }

    /// Bind final cubes to source measurements even when a scan's auto-balance
    /// cancels a changed base density. Model revisions must bump this identifier.
    var bakedMetadata: FilmProfile {
        get throws {
            guard metadata.colour.inputShaper != nil else { return metadata }
            var hash = SHA256()
            hash.update(data: Data("dye-spectral-v1\0".utf8))
            let names = ["stock.json", "spectral.json", "neutral.red.csv", "neutral.green.csv", "neutral.blue.csv",
                         "sensitivity.csv", "dye-density.csv", "observer.csv", "mtf.csv", "rms-granularity.csv"]
            for name in names.sorted() {
                hash.update(data: Data((name + "\0").utf8))
                hash.update(data: Data(SHA256.hash(data: try Data(contentsOf: directory.appendingPathComponent(name)))))
            }
            var result = metadata
            result.colour.sourceFingerprint = hash.finalize().map { String(format: "%02x", $0) }.joined()
            return result
        }
    }

    func characteristicCurves(for payload: String) throws -> [CharacteristicCurve] {
        // Payload references are container names, never paths outside the Curve Set.
        guard !payload.isEmpty, !payload.contains("/"), !payload.contains("\\"), payload != ".", payload != ".." else {
            throw FilmError.invalid("Payload names must be plain filenames")
        }
        let stem = metadata.colour.inputShaper == nil ? (payload as NSString).deletingPathExtension : "neutral"
        let names = metadata.process.isMonochrome ? [stem + ".csv"] : ["red", "green", "blue"].map { stem + "." + $0 + ".csv" }
        return try names.map { try CharacteristicCurve(url: directory.appendingPathComponent($0), exposureRange: metadata.colour.inputShaper == nil ? log10(Double(Float16.leastNonzeroMagnitude))...0 : -10...10) }
    }
}
