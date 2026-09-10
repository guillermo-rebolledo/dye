import Foundation

public struct ProfileCatalogue: Sendable {
    public let profiles: [Profile]
    public init(directory: URL) throws {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "filmprofile" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let loaded = try urls.map { try ProfileContainer.load(from: $0) }
        guard Set(loaded.map(\.id)).count == loaded.count else { throw FilmError.invalid("Duplicate Profile identity in Catalogue") }
        // Alphabetical-by-filename is not a curated Catalogue: it scattered the five
        // synthetic studies through the middle of the browser, so a third of what a
        // first-time user scrolled past was calibration fixtures. Studies now sit
        // together at the end, where a browser can explain them once.
        profiles = loaded.sorted {
            let (left, right) = ($0.metadata.accuracyClaim == .synthetic, $1.metadata.accuracyClaim == .synthetic)
            return left == right ? $0.metadata.displayName < $1.metadata.displayName : !left
        }
    }

    /// The Stocks the Catalogue is a claim about. The studies exist for Golden Images
    /// and Contact Sheet review, both of which load the Catalogue whole.
    public var stocks: [Profile] { profiles.filter { $0.metadata.accuracyClaim != .synthetic } }

    /// The synthetic studies, which model no Stock and claim no accuracy.
    public var studies: [Profile] { profiles.filter { $0.metadata.accuracyClaim == .synthetic } }
    public static func bundled() throws -> ProfileCatalogue {
        guard let directory = Bundle.module.resourceURL?.appendingPathComponent("Catalogue") else {
            throw FilmError.invalid("Bundled Catalogue is missing")
        }
        return try ProfileCatalogue(directory: directory)
    }
}
