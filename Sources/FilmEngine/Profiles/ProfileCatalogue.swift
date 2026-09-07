import Foundation

public struct ProfileCatalogue: Sendable {
    public let profiles: [Profile]
    public init(directory: URL) throws {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "filmprofile" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        profiles = try urls.map { try ProfileContainer.load(from: $0) }
        guard Set(profiles.map(\.id)).count == profiles.count else { throw FilmError.invalid("Duplicate Profile identity in Catalogue") }
    }
    public static func bundled() throws -> ProfileCatalogue {
        guard let directory = Bundle.module.resourceURL?.appendingPathComponent("Catalogue") else {
            throw FilmError.invalid("Bundled Catalogue is missing")
        }
        return try ProfileCatalogue(directory: directory)
    }
}
