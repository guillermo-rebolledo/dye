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
    let result = try await renderer.render(image: .linear(try LinearImage(width: 1, height: 1, rgba: [0.25, 0.25, 0.25, 1])),
        profile: profile, settings: .init(output: .workingSpace))
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
@Test(arguments: ["study-c41", "study-e6", "study-bw-silver", "study-bw-chromogenic", "study-ecn2"])
func everyCurveSetBakesDeterministicallyAndMatchesReference(stock: String) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
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
