import Foundation

public struct Profile: Sendable, Identifiable {
    public var id: String { metadata.id }
    public let metadata: FilmProfile
    let source: Source
    /// Cache identity belongs to the loaded content, independent of its renameable Display Name.
    let cacheID = UUID()
    private let reads = PayloadReadCounter()

    /// Payload bytes this Profile has been asked to read since it was loaded.
    ///
    /// A Colour Cube cache that has stopped caching renders exactly the same pixels
    /// and costs only time, which is why it cannot be caught from the outside without
    /// a count. The count belongs to the loaded Profile rather than to a copy of one:
    /// `Profile` is a value type and the Catalogue hands the same one to every surface
    /// that renders it, so a second sweep reading nothing is the claim under test.
    public var payloadReads: Int { reads.count }
    enum Source: Sendable {
        case memory([String: Data])
        case file(URL, Int, [ProfileContainer.Entry])
    }
    init(metadata: FilmProfile, source: Source) { self.metadata = metadata; self.source = source }

    public init(metadata: FilmProfile, payloads: [String: Data]) throws {
        try metadata.validate()
        self.init(metadata: metadata, source: .memory(payloads))
        let expected = metadata.payloadNames
        guard Set(payloads.keys) == expected else { throw FilmError.invalid("Profile payload references do not match") }
        for (name, bytes) in payloads {
            if name == metadata.monochrome?.densityCurve {
                guard try decodeHalfValues(bytes).count == 1024 else { throw FilmError.invalid("Density Curve must contain 1024 entries") }
            } else {
                let output = metadata.colour.densityOutput
                let outputNames = (output?.lutVariants ?? []) + (output?.printVariants ?? [])
                let size = outputNames.contains { $0.lut == name } ? output!.lutSize : metadata.colour.lutSize
                _ = try ColourCube(size: size, payload: bytes)
            }
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
        reads.record()
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
        try Dictionary(uniqueKeysWithValues: metadata.payloadNames.map { ($0, try readPayload($0)) })
    }

    /// Shared by every copy of one loaded Profile, because that is the thing whose
    /// payloads are being read once or repeatedly.
    private final class PayloadReadCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var reads = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
        func record() { lock.lock(); reads += 1; lock.unlock() }
    }

    private static let identityMetadata: FilmProfile = {
        let url = Bundle.module.url(forResource: "identity", withExtension: "json", subdirectory: "Calibration")!
        return try! JSONDecoder().decode(FilmProfile.self, from: Data(contentsOf: url))
    }()
}
