import Foundation

/// Where an **Export** is written on its way out, and when it stops existing.
///
/// An Export has to become a file before it can reach Photos or a share sheet, and
/// that file is a full-resolution copy of the user's photograph. Writing each one to
/// a fresh UUID-named directory meant every copy the app had ever made stayed in
/// `tmp/` until iOS felt like reclaiming it — an unbounded pile of the user's own
/// pictures, on disk, long after the app had finished with them. One directory,
/// emptied before each write and again at launch, keeps at most the current Export.
///
/// The user loses nothing: an Export that reached Photos is in Photos, and one that
/// was shared was copied by whoever received it. What is left here is scratch.
enum ExportScratch {
    private static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Exports", isDirectory: true)

    /// Empty the directory and return where to write `name`.
    static func prepare(for name: String) throws -> URL {
        clear()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }

    /// Drop whatever is there. Called at launch, so that a crash or a kill mid-share
    /// does not leave a photograph behind for the next session to inherit.
    ///
    /// Silent on failure by design: nothing above this can act on "the temporary
    /// directory would not delete", and refusing to Export over it would be absurd.
    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
