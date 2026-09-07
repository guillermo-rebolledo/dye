import Foundation

public struct Profile: Sendable, Identifiable {
    public var id: String { metadata.id }
    public let metadata: FilmProfile
    let source: Source
    /// Cache identity belongs to the loaded content, independent of its renameable Display Name.
    let cacheID = UUID()
    enum Source: Sendable {
        case memory([String: Data])
        case file(URL, Int, [ProfileContainer.Entry])
    }
    init(metadata: FilmProfile, source: Source) { self.metadata = metadata; self.source = source }

    public init(metadata: FilmProfile, payloads: [String: Data]) throws {
        try metadata.validate()
        self.init(metadata: metadata, source: .memory(payloads))
        let expected = Set(metadata.colour.lutVariants.map(\.lut) + (metadata.monochrome.map { [$0.densityCurve] } ?? []))
        guard Set(payloads.keys) == expected else { throw FilmError.invalid("Profile payload references do not match") }
        for (name, bytes) in payloads {
            if name == metadata.monochrome?.densityCurve {
                guard try decodeHalfValues(bytes).count == 1024 else { throw FilmError.invalid("Density Curve must contain 1024 entries") }
            } else { _ = try ColourCube(size: metadata.colour.lutSize, payload: bytes) }
        }
    }

    /// In-memory Colour Cube profiles are useful for renderer calibration.
    public init(colourCube: ColourCube) {
        var metadata = Self.identityMetadata
        metadata.colour.lutSize = colourCube.size
        self.init(metadata: metadata, source: .memory(["identity.lut3d": colourCube.payload]))
    }
    public static let identity = Profile(colourCube: .identity)

    func readPayload(_ name: String) throws -> Data {
        switch source {
        case .memory(let payloads):
            guard let bytes = payloads[name] else { throw FilmError.invalid("Missing payload \(name)") }
            return bytes
        case .file(let url, let offset, let entries):
            guard let entry = entries.first(where: { $0.name == name }) else { throw FilmError.invalid("Missing payload \(name)") }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset + entry.offset))
            guard let bytes = try handle.read(upToCount: entry.length), bytes.count == entry.length else {
                throw FilmError.invalid("Truncated payload \(name)")
            }
            return bytes
        }
    }

    func readPayloads() throws -> [String: Data] {
        let names = Set(metadata.colour.lutVariants.map(\.lut) + (metadata.monochrome.map { [$0.densityCurve] } ?? []))
        return try Dictionary(uniqueKeysWithValues: names.map { ($0, try readPayload($0)) })
    }

    private static let identityMetadata: FilmProfile = {
        let url = Bundle.module.url(forResource: "identity", withExtension: "json", subdirectory: "Calibration")!
        return try! JSONDecoder().decode(FilmProfile.self, from: Data(contentsOf: url))
    }()
}
