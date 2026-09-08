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
    /// Where the CSVs live. A derived Stock reads its parent's, because it models the
    /// same Emulsion; nothing else about a derivation may reach the spectral model.
    let directory: URL
    /// The authored override document, for a Stock derived from another Profile.
    private let derivation: Data?

    /// The Contrast Filters' shared transmittance table. The glass is a property of
    /// the lens rather than of any Stock, so every monochrome Curve Set reads one
    /// copy of it from a sibling directory rather than restating it.
    var contrastFilterDirectory: URL { directory.deletingLastPathComponent().appendingPathComponent("contrast-filters") }

    /// The Stock's published daylight filter factors, which the validator compares the
    /// derived Contrast Filter Spectral Weights against.
    func publishedFilterFactors() throws -> [ContrastFilter: Double] {
        let lines = try String(contentsOf: directory.appendingPathComponent("filter-factors.csv"), encoding: .utf8)
            .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard lines.first == "filter,daylightFactor" else {
            throw FilmError.invalid("filter-factors.csv: expected filter,daylightFactor")
        }
        var result: [ContrastFilter: Double] = [:]
        for line in lines.dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 2, let filter = ContrastFilter(rawValue: fields[0]), filter != .none,
                  let factor = Double(fields[1]), factor.isFinite, factor >= 1, result[filter] == nil else {
                throw FilmError.invalid("filter-factors.csv: expected one finite factor of at least 1 per Contrast Filter")
            }
            result[filter] = factor
        }
        guard Set(result.keys) == Set(MonochromeSpectralModel.contrastFilters) else {
            throw FilmError.invalid("filter-factors.csv: expected every Contrast Filter")
        }
        return result
    }

    /// Remjet removal changes what light does inside the film and what the box says.
    /// Everything the Colour Cubes are baked from stays with the parent Curve Set.
    static let derivableKeys: Set<String> = ["derivedFrom", "id", "displayName", "process",
                                             "nominalISO", "trueISO", "bloom", "halation", "provenance"]

    init(directory: URL) throws {
        let document = try Data(contentsOf: directory.appendingPathComponent("stock.json"))
        let authored = try JSONSerialization.jsonObject(with: document) as? [String: Any] ?? [:]
        if let parent = authored["derivedFrom"] as? String {
            guard Self.derivableKeys.isSuperset(of: authored.keys) else {
                throw FilmError.invalid("A derived Stock may only override \(Self.derivableKeys.sorted().joined(separator: ", "))")
            }
            self.directory = directory.deletingLastPathComponent().appendingPathComponent(parent)
            derivation = document
            var merged = try JSONSerialization.jsonObject(with: Data(contentsOf: self.directory.appendingPathComponent("stock.json"))) as? [String: Any] ?? [:]
            // Provenance merges key by key, so a derivation records only what it changed.
            if let overrides = authored["provenance"] as? [String: String] {
                var provenance = merged["provenance"] as? [String: String] ?? [:]
                provenance.merge(overrides) { _, new in new }
                merged["provenance"] = provenance
            }
            for (key, value) in authored where key != "provenance" { merged[key] = value }
            metadata = try JSONDecoder().decode(FilmProfile.self, from: JSONSerialization.data(withJSONObject: merged))
        } else {
            self.directory = directory
            derivation = nil
            metadata = try JSONDecoder().decode(FilmProfile.self, from: document)
        }
        try metadata.validate()
        guard (derivation == nil) == (metadata.derivedFrom == nil) else {
            throw FilmError.invalid("A derived Profile must name its parent in its own stock.json")
        }
        guard metadata.colour.sourceFingerprint == nil else {
            throw FilmError.invalid("Source fingerprints are derived by the Baker, not authored in stock.json")
        }
        // 65³ is for a Stock whose curve turns faster than 33 nodes can follow;
        // it costs eight times the payload, so it is the Curve Set's choice, not a default.
        guard metadata.colour.lutSize == 33 || metadata.colour.lutSize == 65 else {
            throw FilmError.invalid("The Baker emits 33³ or 65³ Colour Cubes")
        }
    }

    /// Bind final cubes to source measurements even when a scan's auto-balance
    /// cancels a changed base density. Model revisions must bump this identifier.
    var bakedMetadata: FilmProfile {
        get throws {
            guard metadata.colour.inputShaper != nil else { return metadata }
            var hash = SHA256()
            hash.update(data: Data("dye-spectral-v1\0".utf8))
            // The two spectral branches consume different sources, so each hashes its
            // own list. A Stock cannot change branch without changing its fingerprint.
            var sources = metadata.process.isMonochrome
                ? [directory.appendingPathComponent("density.csv"),
                   contrastFilterDirectory.appendingPathComponent("transmittance.csv"),
                   directory.appendingPathComponent("filter-factors.csv")]
                : ["spectral.json", "neutral.red.csv", "neutral.green.csv", "neutral.blue.csv", "dye-density.csv"]
                    .map(directory.appendingPathComponent)
            sources += ["stock.json", "sensitivity.csv", "observer.csv", "mtf.csv", "rms-granularity.csv"]
                .map(directory.appendingPathComponent)
            for url in sources.sorted(by: { $0.path < $1.path }) {
                hash.update(data: Data((url.lastPathComponent + "\0").utf8))
                hash.update(data: Data(SHA256.hash(data: try Data(contentsOf: url))))
            }
            // The parent's stock.json is already hashed above; this covers the overrides.
            if let derivation {
                hash.update(data: Data("derived.stock.json\0".utf8))
                hash.update(data: Data(SHA256.hash(data: derivation)))
            }
            var result = metadata
            result.colour.sourceFingerprint = hash.finalize().map { String(format: "%02x", $0) }.joined()
            // A B&W Profile's Spectral Weight and Contrast Filters are integrated from
            // the Curve Set rather than authored, so they belong to the baked metadata
            // in the same way the fingerprint does.
            if metadata.process.isMonochrome { result.monochrome = try MonochromeSpectralModel(curves: self).monochrome }
            return result
        }
    }

    func characteristicCurves(for payload: String) throws -> [CharacteristicCurve] {
        // Payload references are container names, never paths outside the Curve Set.
        guard !payload.isEmpty, !payload.contains("/"), !payload.contains("\\"), payload != ".", payload != ".." else {
            throw FilmError.invalid("Payload names must be plain filenames")
        }
        // A B&W Curve Set names its one CSV after its payload; a colour one always
        // measures its Colour Cubes from the same neutral development.
        let stem = metadata.process.isMonochrome || metadata.colour.inputShaper == nil
            ? (payload as NSString).deletingPathExtension : "neutral"
        let names = metadata.process.isMonochrome ? [stem + ".csv"] : ["red", "green", "blue"].map { stem + "." + $0 + ".csv" }
        return try names.map { try CharacteristicCurve(url: directory.appendingPathComponent($0), exposureRange: metadata.colour.inputShaper == nil ? log10(Double(Float16.leastNonzeroMagnitude))...0 : -10...10) }
    }
}
