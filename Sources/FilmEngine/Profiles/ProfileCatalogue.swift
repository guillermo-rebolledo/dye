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
        profiles = loaded.sorted { first, second in
            let isStudy = { (profile: Profile) in profile.metadata.accuracyClaim == .synthetic }
            guard isStudy(first) == isStudy(second) else { return !isStudy(first) }
            return first.metadata.displayName < second.metadata.displayName // bare-display-name: a sort key, never rendered
        }
    }
    public static func bundled() throws -> ProfileCatalogue {
        guard let directory = Bundle.module.resourceURL?.appendingPathComponent("Catalogue") else {
            throw FilmError.invalid("Bundled Catalogue is missing")
        }
        return try ProfileCatalogue(directory: directory)
    }
}
