import Testing
import Foundation
import ImageIO
@testable import FilmEngine

// Export file lifetime, asserted through the renderer seam. An exported frame is a
// full-resolution copy of the user's photograph, so the claim under test is that it
// exists for exactly as long as the user can still act on it and not one moment
// longer — and that a sweep repairing an older install is never destructive beyond
// its own scope.

private func flat(size: Int) throws -> LinearImage {
    var rgba = [Float16](repeating: 0.4, count: size * size * 4)
    for index in stride(from: 3, to: rgba.count, by: 4) { rgba[index] = 1 }
    return try LinearImage(width: size, height: size, rgba: rgba)
}

private func temporaryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("export-file-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

@Test func anExportedFileLivesUntilItIsDiscarded() async throws {
    let renderer = try Renderer()
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = try await renderer.exportFile(image: .linear(flat(size: 64)), profile: .identity,
                                             settings: .init(output: .displayP3), format: .jpeg, in: root)
    // The share affordance outlives the save, so the file survives a finished Export.
    #expect(exists(file.url))
    // Named after the Display Name rather than the Profile id, because ids still carry
    // manufacturer marks and a filename is something the user reads. `filenameStem`
    // owns the rule; `Scripts/check-archive.py` asserts it from the other end.
    #expect(file.url.lastPathComponent == "no-film-stock.jpg")
    #expect(file.byteCount > 0)
    file.discard()
    #expect(!exists(file.url))
    // The containing directory goes with it; a leftover empty directory is still a
    // leftover.
    #expect(!exists(file.url.deletingLastPathComponent()))
    // Dismissing twice is a thing a user can do.
    file.discard()
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}

@Test func releasingTheHandleRemovesTheFileWithoutAnyoneRememberingTo() async throws {
    let renderer = try Renderer()
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    var url: URL?
    do {
        let file = try await renderer.exportFile(image: .linear(flat(size: 64)), profile: .identity,
                                                 settings: .init(output: .displayP3), format: .jpeg, in: root)
        url = file.url
        #expect(exists(file.url))
    }
    // A new Export, a dismissed sheet and a torn-down editor are all just this.
    #expect(!exists(try #require(url)))
}

@Test func anExportedLUTIsOwnedTheSameWayAsAFrame() async throws {
    let renderer = try Renderer()
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = try await renderer.exportedLUTFile(profile: .identity, settings: .init(output: .displayP3), in: root)
    #expect(file.url.lastPathComponent == "no-film-stock.cube")
    #expect(exists(file.url))
    file.discard()
    #expect(!exists(file.url))
}

@Test func cancellingAnExportLeavesNoPartialFileBehind() async throws {
    let renderer = try Renderer()
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let image = try flat(size: 64)
    let task = Task {
        try await renderer.exportFile(image: .linear(image), profile: .identity,
                                      settings: .init(output: .displayP3), format: .jpeg, in: root)
    }
    task.cancel()
    _ = try? await task.value
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}

@Test func theLaunchSweepRemovesTheAppsOwnLeftoversAndNothingElse() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = FileManager.default
    var leftovers: [URL] = []
    for _ in 0..<3 {
        let directory = root.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("portra-400.heic")
        try Data([0, 1, 2]).write(to: file)
        leftovers.append(file)
    }
    // A sweep must never be destructive beyond its own scope, so anything that is not
    // the pattern the app itself generates is left exactly where it was.
    let foreign = root.appendingPathComponent("com.apple.something")
    try manager.createDirectory(at: foreign, withIntermediateDirectories: true)
    let foreignFile = root.appendingPathComponent("notes.txt")
    try Data("keep me".utf8).write(to: foreignFile)

    ExportedFile.sweepLeftovers(in: root)

    for leftover in leftovers { #expect(!exists(leftover)) }
    #expect(!exists(leftovers[0].deletingLastPathComponent()))
    #expect(exists(foreign))
    #expect(try String(contentsOf: foreignFile, encoding: .utf8) == "keep me")
}

@Test func aProfileIdentifierNeverEscapesTheExportDirectory() throws {
    // Nothing in the Catalogue looks like this, and `FilmProfile.validate()` is where
    // that is now enforced. This is the belt to that pair of braces: the safety of a
    // filename does not rest on the Catalogue's contents staying well-behaved.
    for hostile in ["../../Library/Preferences/com.apple.something", "/etc/passwd", "..", ".", "",
                    "a\u{0}b", "réponse", String(repeating: "x", count: 400)] {
        let name = ExportedFile.fileName(hostile, extension: "heic")
        #expect(!name.contains("/") && !name.contains(".."))
        #expect(name.hasSuffix(".heic"))
        let directory = URL(fileURLWithPath: "/tmp/export")
        #expect(directory.appendingPathComponent(name).deletingLastPathComponent().path == directory.path)
    }
    #expect(ExportedFile.fileName("portra-400", extension: "heic") == "portra-400.heic")
}

@Test func anExportedFileCarriesNoLocationAndNoCameraIdentification() async throws {
    let renderer = try Renderer()
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let profile = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "portra-400" })
    let file = try await renderer.exportFile(image: .linear(flat(size: 64)), profile: profile,
                                             settings: .init(output: .displayP3), format: .heif,
                                             options: ExportOptions(creationDate: Date(timeIntervalSince1970: 1_600_000_000)),
                                             in: root)
    defer { file.discard() }
    let source = try #require(CGImageSourceCreateWithURL(file.url as CFURL, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
    #expect(tiff[kCGImagePropertyTIFFMake] == nil && tiff[kCGImagePropertyTIFFModel] == nil)
    let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
    for key in [kCGImagePropertyExifLensModel, kCGImagePropertyExifLensMake,
                kCGImagePropertyExifBodySerialNumber, kCGImagePropertyExifLensSerialNumber] {
        #expect(exif[key] == nil)
    }
    // The date the writer constructs is the one thing it does attach.
    #expect(exif[kCGImagePropertyExifDateTimeOriginal] != nil)
}
