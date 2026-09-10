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

// MARK: - What the app is allowed to call a Stock
//
// `CONTEXT.md` says a Profile carrying any Approximation is an approximation and
// that the app labels it as one *wherever it names the Stock*. That contract was
// silently broken once already: the editor rebuild at `a080f4e` left the label on
// the Filmstrip and dropped it from the other six naming sites, and nothing failed.
// These assert the contract at the Profile codec seam, and
// `everyNamingSiteUsesTheQualifiedDisplayName` fails when a new site is added
// without it, which is the failure mode that actually happened.

@Test func aProfileCarryingAnApproximationQualifiesItsOwnName() throws {
    for profile in try ProfileCatalogue.bundled().profiles {
        let metadata = profile.metadata
        guard metadata.isApproximation else { continue }
        #expect(metadata.nameQualifier == "Approx.", "\(profile.id) is an approximation and does not say so")
        #expect(metadata.qualifiedDisplayName == "Approx. · " + metadata.displayName)
        #expect(metadata.spokenDisplayName == metadata.displayName + ", approximation")
    }
}

@Test func aStockWhoseAccuracyIsUnestablishedIsQualifiedToo() throws {
    let profiles = try ProfileCatalogue.bundled().profiles
    // Nothing in the Catalogue has been compared with a photograph of the film, so
    // nothing may present an unqualified name. `FilmReferences/manifest.json` is the
    // evidence that would change this, and it is still an empty placeholder.
    for profile in profiles where profile.metadata.accuracyClaim == .modelled {
        #expect(profile.metadata.nameQualifier != nil, "\(profile.id) presents itself unqualified")
    }
    // A study is not a claim about any Stock, so it needs no qualifier: its own
    // Display Name already says what it is.
    for profile in profiles where profile.metadata.accuracyClaim == .synthetic {
        #expect(profile.metadata.displayName.contains("synthetic") || profile.id == Profile.identity.id)
        #expect(profile.metadata.nameQualifier == nil)
    }
    #expect(profiles.filter { $0.metadata.accuracyClaim == .validated }.isEmpty,
            "A Profile claims validated accuracy; check it against a held-out capture benchmark first")
}

@Test func anApproximationOutranksTheAccuracyQualifier() throws {
    var metadata = Profile.identity.metadata
    metadata.accuracy = .modelled
    #expect(metadata.nameQualifier == "Modelled")
    metadata.provenance["grain.densityExtrapolation"] = .approximation
    #expect(metadata.nameQualifier == "Approx.")
    metadata.accuracy = .validated
    #expect(metadata.nameQualifier == "Approx.", "A borrowed measurement is the stronger caveat")
}

@Test func accuracySurvivesTheProfileCodec() throws {
    for profile in try ProfileCatalogue.bundled().profiles {
        let decoded = try ProfileContainer.decode(ProfileContainer.encode(profile))
        #expect(decoded.metadata.accuracy == profile.metadata.accuracy, "\(profile.id) lost its accuracy claim")
    }
}

@Test func identityProfileDecodesFromItsCompiledSource() throws {
    // `Profile.identity` backs the first frame, so its metadata is compiled in rather
    // than read from the resource bundle. Nothing else proves the literal still parses.
    let metadata = try JSONDecoder().decode(FilmProfile.self, from: Data(Profile.identitySource.utf8))
    #expect(metadata == Profile.identity.metadata)
    #expect(metadata.displayName == "No Film Stock")
    #expect(metadata.accuracy == .synthetic)
}

/// Every place the interface renders a Stock's name must render the qualifier with
/// it. This reads the app's own sources because the app is not in this package and
/// there is no other way to assert it — and because the contract is exactly the kind
/// that a redesign drops without any test noticing.
@Test func everyNamingSiteUsesTheQualifiedDisplayName() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let sources = ["FilmApp", "Sources/FilmEngine"].flatMap { directory -> [URL] in
        let base = root.appendingPathComponent(directory)
        return FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
    }
    #expect(sources.count > 20, "Found no app sources to check; the layout moved")

    for url in sources {
        // `FilmProfile.swift` defines the qualifier and necessarily reads the bare name.
        guard url.lastPathComponent != "FilmProfile.swift" else { continue }
        for (number, line) in try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: .newlines).enumerated() {
            guard line.contains("metadata.displayName") else { continue }
            // A site that genuinely wants the bare name says so in the line, with a
            // reason. Exempting in the test file instead would put the justification
            // where nobody editing the naming site would ever read it, and an
            // exemption with no reason is just a way of turning the check off.
            if let marker = line.range(of: "// bare-display-name:") {
                let reason = line[marker.upperBound...].trimmingCharacters(in: .whitespaces)
                #expect(reason.count >= 12, "\(url.lastPathComponent):\(number + 1) exempts itself without a reason")
                continue
            }
            let site = "\(url.lastPathComponent):\(number + 1)"
            Issue.record("\(site) names a Stock with its bare Display Name; use qualifiedDisplayName or spokenDisplayName")
        }
    }
}
