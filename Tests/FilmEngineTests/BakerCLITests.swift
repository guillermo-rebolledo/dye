#if os(macOS)
import Foundation
import Testing
import FilmEngine

private let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func baker(_ arguments: [String]) throws -> (Int32, String) {
    let process = Process()
    process.executableURL = ProcessInfo.processInfo.environment["PROFILE_BAKER_EXECUTABLE"].map(URL.init(fileURLWithPath:))
        ?? repository.appendingPathComponent(".build/debug/ProfileBaker")
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: bytes, as: UTF8.self))
}

@Test func bakerCLIEmitsLoadableProfileAndNumericallyValidatesStepWedge() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let curves = repository.appendingPathComponent("Curves/study-c41")
    let output = directory.appendingPathComponent("study.filmprofile")
    let (status, message) = try baker(["bake", curves.path, output.path])
    #expect(status == 0, Comment(rawValue: message))
    let catalogue = try ProfileCatalogue(directory: directory)
    let profile = try #require(catalogue.profiles.first)
    #expect(profile.metadata.displayName == "Colour negative study (synthetic)")
    let renderer = try Renderer()
    // Density Space is read with the runtime scan disabled.
    let result = try await renderer.render(image: .linear(try LinearImage(width: 1, height: 1, rgba: [0.25, 0.25, 0.25, 1])),
        profile: profile, settings: .init(output: .workingSpace, outputStage: OutputStage.none))
    // This literal is the committed reference density at log10(0.25).
    #expect(abs(Float(result.rgba[0]) - 0.7) < 0.002)
    let report = directory.appendingPathComponent("wedge")
    let (validationStatus, validationMessage) = try baker(["validate", curves.path, output.path, report.path, "0.03"])
    #expect(validationStatus == 0, Comment(rawValue: validationMessage))
    #expect(FileManager.default.fileExists(atPath: report.appendingPathExtension("svg").path))
    #expect(FileManager.default.fileExists(atPath: report.appendingPathExtension("csv").path))
}
#endif

#if os(macOS)
@Test(arguments: ["study-c41", "study-e6", "study-bw-silver", "study-bw-chromogenic", "study-ecn2", "portra-400",
                  "vision3-50d", "vision3-250d", "vision3-200t", "vision3-500t", "cinestill-800t",
                  "tri-x-400", "t-max-100"])
func everyCurveSetBakesDeterministicallyAndMatchesReference(stock: String) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    // A derived Stock reads its parent's Curve Set from the sibling directory.
    let curves = repository.appendingPathComponent("Curves/\(stock)")
    let output = directory.appendingPathComponent("a.filmprofile")
    let second = directory.appendingPathComponent("b.filmprofile")
    for url in [output, second] {
        let (status, message) = try baker(["bake", curves.path, url.path])
        #expect(status == 0, Comment(rawValue: message))
    }
    #expect(try Data(contentsOf: output) == Data(contentsOf: second))
    let bundled = repository.appendingPathComponent("Sources/FilmEngine/Catalogue/\(stock).filmprofile")
    #expect(try Data(contentsOf: output) == Data(contentsOf: bundled))
    let (status, message) = try baker(["validate", curves.path, output.path, directory.appendingPathComponent("wedge").path, "0.03"])
    #expect(status == 0, Comment(rawValue: message))
}

@Test func bakerRejectsMalformedCSVsAndValidationDetectsChangedReferences() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let curves = directory.appendingPathComponent("curves")
    try FileManager.default.copyItem(at: repository.appendingPathComponent("Curves/study-bw-silver"), to: curves)
    let output = directory.appendingPathComponent("stock.filmprofile")
    #expect(try baker(["bake", curves.path, output.path]).0 == 0)
    let reference = curves.appendingPathComponent("density.csv")
    let valid = try String(contentsOf: reference, encoding: .utf8)
    // Alter the source of truth while keeping the previously baked profile.
    try valid.replacingOccurrences(of: ",0.7", with: ",1.7").write(to: reference, atomically: true, encoding: .utf8)
    let (status, message) = try baker(["validate", curves.path, output.path, directory.appendingPathComponent("bad-wedge").path, "0.03"])
    #expect(status != 0)
    #expect(message.contains("exceeds tolerance"))
    let malformed = ["logExposure,density\n-1,0.5\n-1,1\n", "logExposure,density\n0,1\n-1,0.5\n",
                     "logExposure,density\n-1,nan\n0,1\n", "exposure,density\n-1,0.5\n0,1\n",
                     "logExposure,density\n-1,0.5,extra\n0,1\n"]
    for csv in malformed {
        try csv.write(to: reference, atomically: true, encoding: .utf8)
        let destination = directory.appendingPathComponent("invalid.filmprofile")
        #expect(try baker(["bake", curves.path, destination.path]).0 != 0)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
    #expect(try baker(["validate", curves.path, output.path, directory.appendingPathComponent("wedge").path, "nan"]).0 != 0)
}
#endif

#if os(macOS)
@Test func portraCLIEmitsFourSpectralVariantsAndPassesDensityGate() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let curves = repository.appendingPathComponent("Curves/portra-400")
    let output = directory.appendingPathComponent("portra.filmprofile")
    let (status, message) = try baker(["bake", curves.path, output.path])
    try #require(status == 0, Comment(rawValue: message))
    let profile = try ProfileContainer.decode(Data(contentsOf: output))
    #expect(profile.metadata.colour.lutSize == 33)
    #expect(profile.metadata.colour.lutVariants.map(\.pushStops) == [-1, 0, 1, 2])
    #expect(profile.metadata.provenance["grain.rmsGranularity"] == .artistic)
    let (validationStatus, report) = try baker(["validate", curves.path, output.path,
        directory.appendingPathComponent("wedge").path, "0.03"])
    #expect(validationStatus == 0, Comment(rawValue: report))
}
#endif

#if os(macOS)
/// Copies a Curve Set together with the RA-4 paper it prints onto, which the Baker
/// reads from a sibling directory the way a monochrome Curve Set reads the Contrast
/// Filters' transmittance table.
private func printingCurveSet(_ stock: String, in directory: URL) throws -> URL {
    let curves = directory.appendingPathComponent("Curves")
    try FileManager.default.createDirectory(at: curves, withIntermediateDirectories: true)
    for name in [stock, "ra4-paper"] {
        try FileManager.default.copyItem(at: repository.appendingPathComponent("Curves/\(name)"),
                                         to: curves.appendingPathComponent(name))
    }
    return curves.appendingPathComponent(stock)
}

@Test func spectralValidationRejectsAProfileFromDifferentSourceMeasurements() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let curves = try printingCurveSet("portra-400", in: directory)
    let output = directory.appendingPathComponent("portra.filmprofile")
    let (status, message) = try baker(["bake", curves.path, output.path])
    try #require(status == 0, Comment(rawValue: message))
    // A uniform change in absolute base density cancels in an auto-balanced scan.
    // Validation must still detect that the profile came from different measurements.
    let red = curves.appendingPathComponent("neutral.red.csv")
    let changed = try String(contentsOf: red, encoding: .utf8).components(separatedBy: .newlines).map { line in
        let fields = line.split(separator: ",")
        guard fields.count == 2, let density = Double(fields[1]) else { return line }
        return "\(fields[0]),\(density + 0.1)"
    }.joined(separator: "\n")
    try changed.write(to: red, atomically: true, encoding: .utf8)
    let (validationStatus, _) = try baker(["validate", curves.path, output.path, directory.appendingPathComponent("wedge").path, "0.03"])
    #expect(validationStatus != 0)
}
#endif

#if os(macOS)
@Test func portraDevelopmentChangesShapeAroundReferenceGray() async throws {
    let profile = try ProfileContainer.load(from: repository.appendingPathComponent("Sources/FilmEngine/Catalogue/portra-400.filmprofile"))
    let shaper = try #require(profile.metadata.colour.inputShaper)
    #expect(profile.metadata.colour.cubeOutput == .displayLinearRec2020)
    #expect(profile.metadata.colour.sourceFingerprint?.count == 64)
    // Scene-linear light for shaped coordinates 0.3 and 0.7 either side of mid-grey.
    func scene(_ coordinate: Double) -> Float16 {
        let logH = shaper.minimumLogExposure + coordinate * (shaper.maximumLogExposure - shaper.minimumLogExposure)
        return Float16(0.18 * pow(10, logH - shaper.middleGrayLogExposure))
    }
    let image = try LinearImage(width: 3, height: 1, rgba: [scene(0.3), scene(0.3), scene(0.3), 1, 0.18, 0.18, 0.18, 1, scene(0.7), scene(0.7), scene(0.7), 1])
    let renderer = try Renderer()
    var shadows: [Float] = []
    var highlights: [Float] = []
    for offset in [-1.0, 0, 1, 2] {
        // Cancel the push rating so each variant is probed at the same physical exposure.
        let result = try await renderer.render(image: .linear(image), profile: profile,
            settings: .init(output: .workingSpace, exposureStops: offset, developmentOffset: offset))
        for c in 0..<3 { #expect(abs(Float(result.rgba[4 + c]) - 0.18) < 0.006) }
        shadows.append(Float(result.rgba[0]))
        highlights.append(Float(result.rgba[8]))
    }
    #expect(zip(shadows, shadows.dropFirst()).allSatisfy { $0 > $1 })
    #expect(zip(highlights, highlights.dropFirst()).allSatisfy { $0 < $1 })
}

@Test(arguments: ["dir", "sensitivity", "dyes"])
func portraChromaticResponseDependsOnSpectralInputs(feature: String) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let curves = try printingCurveSet("portra-400", in: directory)
    if feature == "dir" {
        let url = curves.appendingPathComponent("spectral.json")
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["dirCouplers"] = [[0, 0, 0], [0, 0, 0], [0, 0, 0]]
        try JSONSerialization.data(withJSONObject: json).write(to: url)
    } else {
        let url = curves.appendingPathComponent(feature == "sensitivity" ? "sensitivity.csv" : "dye-density.csv")
        let changed = try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines).map { line in
            var fields = line.components(separatedBy: ",")
            guard let nm = Double(fields[0]), fields.count >= 3 else { return line }
            if feature == "sensitivity" { fields.swapAt(1, 2) }
            else if nm >= 570, let density = Double(fields[2]) { fields[2] = String(density + 0.4) }
            return fields.joined(separator: ",")
        }.joined(separator: "\n")
        try changed.write(to: url, atomically: true, encoding: .utf8)
    }
    let output = directory.appendingPathComponent("altered.filmprofile")
    let (status, message) = try baker(["bake", curves.path, output.path])
    try #require(status == 0, Comment(rawValue: message))
    let original = try ProfileContainer.load(from: repository.appendingPathComponent("Sources/FilmEngine/Catalogue/portra-400.filmprofile"))
    let altered = try ProfileContainer.load(from: output)
    let input = try LinearImage(width: 4, height: 1, rgba: [0.55, 0.35, 0.2, 1, 0.3, 0.6, 0.4, 1, 0.4, 0.3, 0.6, 1, 0.5, 0.5, 0.5, 1])
    let renderer = try Renderer()
    let before = try await renderer.render(image: .linear(input), profile: original, settings: .init(output: .workingSpace))
    let after = try await renderer.render(image: .linear(input), profile: altered, settings: .init(output: .workingSpace))
    let differences = zip(before.rgba.prefix(12), after.rgba.prefix(12)).map { abs(Float($0) - Float($1)) }
    #expect(differences.max()! > 0.002)
    // Neutral Characteristic Curves already contain DIR, so ablation must preserve gray.
    if feature == "dir" {
        for c in 12..<15 { #expect(abs(Float(before.rgba[c]) - Float(after.rgba[c])) < 0.001) }
    }
}

@Test func spectralCLIRejectsMisalignedBandsAndMissingProvenance() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let curves = try printingCurveSet("portra-400", in: directory)
    let sensitivity = curves.appendingPathComponent("sensitivity.csv")
    let valid = try String(contentsOf: sensitivity, encoding: .utf8)
    let destination = directory.appendingPathComponent("invalid.filmprofile")
    for malformed in [valid.replacingOccurrences(of: "410,", with: "411,"), valid.replacingOccurrences(of: "410,", with: "400,"), "wavelengthNM,red,green,blue\n400,nan,1,1\n700,1,1,1\n"] {
        try malformed.write(to: sensitivity, atomically: true, encoding: .utf8)
        #expect(try baker(["bake", curves.path, destination.path]).0 != 0)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
    try valid.write(to: sensitivity, atomically: true, encoding: .utf8)
    let metadata = curves.appendingPathComponent("stock.json")
    var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
    var provenance = try #require(json["provenance"] as? [String: String])
    provenance.removeValue(forKey: "spectral.dirCouplers")
    json["provenance"] = provenance
    try JSONSerialization.data(withJSONObject: json).write(to: metadata)
    #expect(try baker(["bake", curves.path, destination.path]).0 != 0)
}
#endif

#if os(macOS)
/// Copies the Cinestill derivation and the Vision3 Curve Set it reads into one tree.
private func derivedCurveSets(in directory: URL) throws -> URL {
    let curves = directory.appendingPathComponent("Curves")
    try FileManager.default.createDirectory(at: curves, withIntermediateDirectories: true)
    // 500T prints, so the paper it prints onto has to come along too.
    for stock in ["vision3-500t", "cinestill-800t", "ra4-paper"] {
        try FileManager.default.copyItem(at: repository.appendingPathComponent("Curves/\(stock)"),
                                         to: curves.appendingPathComponent(stock))
    }
    return curves
}

@Test func aDerivedStockMayOnlyRestateWhatRemjetRemovalChanges() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let curves = try derivedCurveSets(in: directory)
    let metadata = curves.appendingPathComponent("cinestill-800t/stock.json")
    let authored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
    let output = directory.appendingPathComponent("derived.filmprofile")
    #expect(try baker(["bake", curves.appendingPathComponent("cinestill-800t").path, output.path]).0 == 0)
    // Anything the Colour Cubes are baked from has to stay with the parent, and a
    // derivation must name a parent that exists.
    for (key, value) in [("balance", 5500), ("mtf", ["cyclesPerMM": [1, 2], "response": [1, 0.5]]),
                         ("grain", ["rmsGranularity": 0.5]), ("derivedFrom", "portra-400")] as [(String, Any)] {
        var changed = authored
        changed[key] = value
        try JSONSerialization.data(withJSONObject: changed).write(to: metadata)
        let invalid = directory.appendingPathComponent("invalid.filmprofile")
        let (status, message) = try baker(["bake", curves.appendingPathComponent("cinestill-800t").path, invalid.path])
        #expect(status != 0, Comment(rawValue: "overriding \(key) was accepted: \(message)"))
        #expect(!FileManager.default.fileExists(atPath: invalid.path))
    }
    // A Profile whose parent Curve Set has since changed is rejected before any
    // numerical comparison, exactly as a Profile baked from its own sources is.
    try JSONSerialization.data(withJSONObject: authored).write(to: metadata)
    let red = curves.appendingPathComponent("vision3-500t/neutral.red.csv")
    let shifted = try String(contentsOf: red, encoding: .utf8).components(separatedBy: .newlines).map { line -> String in
        let fields = line.split(separator: ",")
        guard fields.count == 2, let density = Double(fields[1]) else { return line }
        return "\(fields[0]),\(density + 0.1)"
    }.joined(separator: "\n")
    try shifted.write(to: red, atomically: true, encoding: .utf8)
    let (status, _) = try baker(["validate", curves.appendingPathComponent("cinestill-800t").path, output.path,
                                 directory.appendingPathComponent("wedge").path, "0.03"])
    #expect(status != 0)
}
#endif

#if os(macOS)
/// Copies a monochrome Curve Set together with the Contrast Filter transmittance
/// table it reads from a sibling directory.
private func monochromeCurveSets(_ stock: String, in directory: URL) throws -> URL {
    let curves = directory.appendingPathComponent("Curves")
    try FileManager.default.createDirectory(at: curves, withIntermediateDirectories: true)
    for name in [stock, "contrast-filters"] {
        try FileManager.default.copyItem(at: repository.appendingPathComponent("Curves/\(name)"),
                                         to: curves.appendingPathComponent(name))
    }
    return curves
}

@Test(arguments: ["tri-x-400", "t-max-100"])
func aMonochromeCurveSetDerivesItsCollapseAndRefusesAnAuthoredOne(stock: String) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let curves = try monochromeCurveSets(stock, in: directory).appendingPathComponent(stock)
    let metadata = curves.appendingPathComponent("stock.json")
    let authored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
    let output = directory.appendingPathComponent("bw.filmprofile")
    let (status, message) = try baker(["bake", curves.path, output.path])
    try #require(status == 0, Comment(rawValue: message))
    let profile = try ProfileContainer.decode(Data(contentsOf: output))
    #expect(profile.metadata.colour.lutVariants.isEmpty)
    #expect(profile.metadata.monochrome?.contrastFilters?.count == 5)
    // The Density Curve is the entire payload: 1024 float16 entries and no cube.
    let bytes = try Data(contentsOf: output).count
    #expect(bytes < 16 + 2048 + 8192)
    // Neither derived field may be authored, exactly as with the source fingerprint.
    for key in ["spectralWeight", "contrastFilters"] {
        var changed = authored
        var monochrome = try #require(changed["monochrome"] as? [String: Any])
        monochrome[key] = key == "spectralWeight" ? [0.3, 0.4, 0.3]
            : [["filter": "yellow", "spectralWeight": [0.3, 0.4, 0.3]]]
        changed["monochrome"] = monochrome
        try JSONSerialization.data(withJSONObject: changed).write(to: metadata)
        let invalid = directory.appendingPathComponent("invalid.filmprofile")
        let (code, text) = try baker(["bake", curves.path, invalid.path])
        #expect(code != 0, Comment(rawValue: "authoring monochrome.\(key) was accepted: \(text)"))
        #expect(!FileManager.default.fileExists(atPath: invalid.path))
    }
    try JSONSerialization.data(withJSONObject: authored).write(to: metadata)
    #expect(try baker(["bake", curves.path, output.path]).0 == 0)
}

@Test func theMonochromeCollapseFollowsTheDigitisedSensitivityAndTheGlassInFrontOfIt() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = try monochromeCurveSets("tri-x-400", in: directory)
    let curves = root.appendingPathComponent("tri-x-400")
    let output = directory.appendingPathComponent("bw.filmprofile")
    try #require(try baker(["bake", curves.path, output.path]).0 == 0)
    let original = try #require(try ProfileContainer.decode(Data(contentsOf: output)).metadata.monochrome)
    // Halve the red end of the sensitivity curve and the collapse must follow it.
    let sensitivity = curves.appendingPathComponent("sensitivity.csv")
    let valid = try String(contentsOf: sensitivity, encoding: .utf8)
    let dimmed = valid.components(separatedBy: .newlines).map { line -> String in
        let fields = line.components(separatedBy: ",")
        guard fields.count == 2, let nm = Double(fields[0]), let value = Double(fields[1]) else { return line }
        return nm >= 600 ? "\(fields[0]),\(value / 2)" : line
    }.joined(separator: "\n")
    try dimmed.write(to: sensitivity, atomically: true, encoding: .utf8)
    let altered = directory.appendingPathComponent("altered.filmprofile")
    try #require(try baker(["bake", curves.path, altered.path]).0 == 0)
    let changed = try #require(try ProfileContainer.decode(Data(contentsOf: altered)).metadata.monochrome)
    let before = try #require(original.weight(for: .none)), after = try #require(changed.weight(for: .none))
    #expect(after[0] < before[0] - 0.02)
    // A red Contrast Filter is where a lost red end shows most, so its factor climbs.
    let beforeRed = try #require(original.filterFactorStops(.red))
    let afterRed = try #require(changed.filterFactorStops(.red))
    #expect(afterRed > beforeRed + 0.5)
    // And the validator notices, because the published factor did not change.
    let (status, message) = try baker(["validate", curves.path, altered.path,
                                       directory.appendingPathComponent("wedge").path, "0.03"])
    #expect(status != 0)
    #expect(message.contains("exceeds tolerance"))
    try valid.write(to: sensitivity, atomically: true, encoding: .utf8)

    // The transmittance table is shared authoring input, so changing it invalidates
    // every monochrome Profile baked against the old one.
    let glass = root.appendingPathComponent("contrast-filters/transmittance.csv")
    let opaque = try String(contentsOf: glass, encoding: .utf8).replacingOccurrences(of: "0.900000", with: "0.100000")
    try opaque.write(to: glass, atomically: true, encoding: .utf8)
    #expect(try baker(["validate", curves.path, output.path,
                       directory.appendingPathComponent("stale").path, "0.03"]).0 != 0)
}

@Test func aMonochromeCurveSetRejectsMalformedSpectralInput() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = try monochromeCurveSets("t-max-100", in: directory)
    let curves = root.appendingPathComponent("t-max-100")
    let destination = directory.appendingPathComponent("invalid.filmprofile")
    let sensitivity = curves.appendingPathComponent("sensitivity.csv")
    let valid = try String(contentsOf: sensitivity, encoding: .utf8)
    for malformed in [valid.replacingOccurrences(of: "410,", with: "411,"),
                      valid.replacingOccurrences(of: "410,", with: "400,"),
                      "wavelengthNM,sensitivity\n400,nan\n700,1\n",
                      "wavelengthNM,red,green,blue\n400,1,1,1\n700,1,1,1\n"] {
        try malformed.write(to: sensitivity, atomically: true, encoding: .utf8)
        #expect(try baker(["bake", curves.path, destination.path]).0 != 0)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
    try valid.write(to: sensitivity, atomically: true, encoding: .utf8)
    // Transmittance outside 0...1 is not glass, and a missing filter is not a filter.
    let glass = root.appendingPathComponent("contrast-filters/transmittance.csv")
    let table = try String(contentsOf: glass, encoding: .utf8)
    for malformed in [table.replacingOccurrences(of: "0.900000", with: "1.900000"),
                      table.replacingOccurrences(of: ",red", with: ",crimson")] {
        try malformed.write(to: glass, atomically: true, encoding: .utf8)
        #expect(try baker(["bake", curves.path, destination.path]).0 != 0)
    }
    try table.write(to: glass, atomically: true, encoding: .utf8)
    // A published filter factor the Curve Set does not name is an incomplete table.
    let factors = curves.appendingPathComponent("filter-factors.csv")
    let published = try String(contentsOf: factors, encoding: .utf8)
    try published.replacingOccurrences(of: "green,6.000000\n", with: "")
        .write(to: factors, atomically: true, encoding: .utf8)
    try #require(try baker(["bake", curves.path, destination.path]).0 == 0)
    #expect(try baker(["validate", curves.path, destination.path,
                       directory.appendingPathComponent("wedge").path, "0.03"]).0 != 0)
}
#endif
