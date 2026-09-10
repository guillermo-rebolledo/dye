import Foundation
import Testing
@testable import FilmEngine

@Test(arguments: FilmProcess.allCases)
func profileCodecRoundTripsEveryProcess(_ process: FilmProcess) throws {
    let profile = try #require(ProfileCatalogue.bundled().profiles.first { $0.metadata.process == process })
    let bytes = try ProfileContainer.encode(profile)
    let decoded = try ProfileContainer.decode(bytes)
    #expect(decoded.metadata == profile.metadata)
    #expect(try ProfileContainer.encode(decoded) == bytes)
    #expect((decoded.metadata.monochrome != nil) == process.isMonochrome)
    #expect(decoded.metadata.provenance["halation.strength"] == .artistic)
}

@Test func sparseVariantsAndDisplayNameAreIndependentOfPayloadIdentity() throws {
    let original = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "study-c41" })
    let encoded = try ProfileContainer.encode(original)
    let decoded = try ProfileContainer.decode(encoded)
    #expect(decoded.metadata.colour.lutVariants.map(\.pushStops) == [0, 2])
    var metadata = decoded.metadata
    metadata.displayName = "A renamed Stock"
    // Reuse payload bytes via the public codec without reaching into renderer internals.
    let cube = ColourCube.identity.payload
    let renamed = try Profile(metadata: metadata, payloads: ["neutral.lut3d": cube, "push2.lut3d": cube])
    let result = try ProfileContainer.decode(ProfileContainer.encode(renamed))
    #expect(result.id == original.id)
    #expect(result.metadata.colour == original.metadata.colour)
    #expect(result.metadata.displayName == "A renamed Stock")
    #expect(result.metadata.grain.grainRadiusMicrons == 1.2)
    #expect(result.metadata.halation.radiusMicrons == [220, 90, 45])
}

@Test func malformedContainersAndIncompleteProvenanceFail() throws {
    let profile = try #require(ProfileCatalogue.bundled().profiles.first { $0.metadata.process == .c41 })
    let bytes = try ProfileContainer.encode(profile)
    for cut in [0, 7, 15, 16, bytes.count - 1] {
        #expect(throws: (any Error).self) { try ProfileContainer.decode(Data(bytes.prefix(cut))) }
    }
    var unsupported = bytes
    unsupported[8] = 99
    #expect(throws: (any Error).self) { try ProfileContainer.decode(unsupported) }
    #expect(throws: (any Error).self) { try ProfileContainer.decode(bytes + Data([0])) }
    var metadata = profile.metadata
    metadata.provenance.removeValue(forKey: "grain.grainRadiusMicrons")
    #expect(throws: (any Error).self) { try Profile(metadata: metadata, payloads: [:]) }
    metadata = profile.metadata
    metadata.halation.radiusMicrons = [-1, 2, 3]
    #expect(throws: (any Error).self) { try Profile(metadata: metadata, payloads: [:]) }
}

@Test func metadataLoadsWithoutReadingInvalidPayloadButRenderingRejectsIt() async throws {
    let profile = try #require(ProfileCatalogue.bundled().profiles.first { $0.metadata.process == .c41 })
    var bytes = try ProfileContainer.encode(profile)
    let headerLength = (0..<4).reduce(0) { $0 | Int(bytes[12 + $1]) << ($1 * 8) }
    // First half value becomes +infinity. Metadata-only loading must still work.
    bytes[16 + headerLength] = 0
    bytes[17 + headerLength] = 0x7c
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".filmprofile")
    defer { try? FileManager.default.removeItem(at: url) }
    try bytes.write(to: url)
    let lazy = try ProfileContainer.load(from: url)
    #expect(lazy.metadata == profile.metadata)
    #expect(throws: (any Error).self) { try ProfileContainer.decode(bytes) }
    let renderer = try Renderer()
    await #expect(throws: (any Error).self) {
        try await renderer.render(image: .linear(try LinearImage(width: 1, height: 1, rgba: [0.5, 0.5, 0.5, 1])), profile: lazy)
    }
}

@Test func spectralCoordinateContractSurvivesCodecAndRejectsInvalidDomains() throws {
    let original = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "portra-400" })
    let decoded = try ProfileContainer.decode(ProfileContainer.encode(original))
    #expect(decoded.metadata.colour == original.metadata.colour)
    let cube = ColourCube.identity.payload
    // Every payload the Profile references, so each rejection below is the schema
    // violation it names rather than a payload set that no longer matches.
    let payloads = Dictionary(uniqueKeysWithValues: original.metadata.payloadNames.map { ($0, cube) })
    var invalid = original.metadata
    invalid.colour.inputShaper?.minimumLogExposure = 1
    #expect(throws: (any Error).self) { try Profile(metadata: invalid, payloads: payloads) }
    invalid = original.metadata
    invalid.colour.inputShaper?.maximumLogExposure = .infinity
    #expect(throws: (any Error).self) { try Profile(metadata: invalid, payloads: payloads) }
    invalid = original.metadata
    invalid.colour.inputShaper = nil
    #expect(throws: (any Error).self) { try Profile(metadata: invalid, payloads: payloads) }
    invalid = original.metadata
    invalid.colour.cubeOutput = .displayLinearRec2020
    #expect(throws: (any Error).self) { try Profile(metadata: invalid, payloads: payloads) }
    invalid = original.metadata
    invalid.provenance.removeValue(forKey: "colour.inputShaper")
    #expect(throws: (any Error).self) { try Profile(metadata: invalid, payloads: payloads) }
}

@Test func printVariantsMustCoverTheSameNegativeTheScanDoes() throws {
    let original = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "vision3-250d" })
    let decoded = try ProfileContainer.decode(ProfileContainer.encode(original))
    #expect(decoded.metadata.colour.printVariants == original.metadata.colour.printVariants)
    func payloads(_ metadata: FilmProfile) -> [String: Data] {
        let output = metadata.colour.densityOutput
        let outputNames = Set(((output?.lutVariants ?? []) + (output?.printVariants ?? [])).map(\.lut))
        return Dictionary(uniqueKeysWithValues: metadata.payloadNames.map { name in
            let size = outputNames.contains(name) ? output!.lutSize : metadata.colour.lutSize
            return (name, Data(repeating: 0, count: size * size * size * 8))
        })
    }
    #expect(throws: Never.self) { try Profile(metadata: original.metadata, payloads: payloads(original.metadata)) }
    // A Print that covers different Development Offsets from the scan, one that
    // borrows the scan's own payload, and a Print on a Stock with no spectral model
    // to print from are each rejected rather than approximated.
    var invalid = original.metadata
    invalid.colour.printVariants?.removeLast()
    #expect(throws: (any Error).self) { try Profile(metadata: invalid, payloads: payloads(invalid)) }
    invalid = original.metadata
    invalid.colour.densityOutput?.printVariants?[0].lut = try #require(invalid.colour.lutVariants.first).lut
    #expect(throws: (any Error).self) { try Profile(metadata: invalid, payloads: payloads(invalid)) }
    invalid = original.metadata
    invalid.provenance.removeValue(forKey: "colour.printVariants")
    #expect(throws: (any Error).self) { try Profile(metadata: invalid, payloads: payloads(invalid)) }
    // A reversal Stock has no negative for an enlarger to shine through.
    var reversal = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "provia-100f" }).metadata
    reversal.colour.printVariants = original.metadata.colour.printVariants
    reversal.provenance["colour.printVariants"] = .artistic
    #expect(throws: (any Error).self) { try Profile(metadata: reversal, payloads: payloads(reversal)) }
}

@Test func halfPayloadsPreserveBitsAndRejectEveryNonfiniteEncoding() throws {
    let bits: [UInt16] = [0x0000, 0x8000, 0x0001, 0x0400, 0x3c00, 0xbc00, 0x7bff, 0xfbff]
    let expected = Array(repeating: bits, count: 4).flatMap { $0 }
    let bytes = Data(expected.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8($0 >> 8)] })
    let cube = try ColourCube(size: 2, payload: bytes)
    #expect(cube.rgba.map(\.bitPattern) == expected)
    #expect(cube.payload == bytes)
    for invalid: UInt16 in [0x7c00, 0xfc00, 0x7c01, 0x7e00, 0xfe00] {
        var bad = bytes
        bad[0] = UInt8(truncatingIfNeeded: invalid)
        bad[1] = UInt8(invalid >> 8)
        #expect(throws: FilmError.self) { try ColourCube(size: 2, payload: bad) }
    }
}

@Test func packedHalfValidationCoversEveryEncodingAndTailLane() throws {
    let finite = (0...UInt16.max).filter { $0 & 0x7c00 != 0x7c00 }
    let bytes = Data(finite.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8($0 >> 8)] })
    #expect(try decodeHalfValues(bytes).map(\.bitPattern) == finite)
    // Four packed lanes followed by three scalar tail lanes. Exercise every
    // infinity/NaN encoding in every position, including negative encodings.
    for value in (0...UInt16.max).filter({ $0 & 0x7c00 == 0x7c00 }) {
        for lane in 0..<7 {
            var bad = Data(repeating: 0, count: 14)
            bad[2 * lane] = UInt8(truncatingIfNeeded: value)
            bad[2 * lane + 1] = UInt8(value >> 8)
            #expect(throws: FilmError.self) { try decodeHalfValues(bad) }
        }
    }
    for count in 0..<8 {
        let finiteTail = Data(repeating: 0, count: count * 2)
        #expect(try decodeHalfValues(finiteTail).count == count)
    }
    #expect(throws: FilmError.self) { try decodeHalfValues(Data([0])) }
}
