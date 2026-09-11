import Foundation

/// A file the Export path wrote, and still owns.
///
/// The engine owns the lifetime rather than the app because an exported frame is a
/// full-resolution copy of the user's photograph, and the app has no reason to keep
/// one. The rule is reachability rather than success: the file lives for exactly as
/// long as the user can still act on it — share it, read its name off the finished
/// sheet — which means it must outlive the save to Photos and must not outlive the
/// sheet. Releasing the handle removes the file, so a new Export, a dismissed sheet
/// and a torn-down editor all clean up without anyone remembering to; `discard()` is
/// the explicit form of the same thing and is safe to call twice.
public final class ExportedFile: @unchecked Sendable {
    /// The written file itself. It is the only thing in a directory of its own, so
    /// removing the file means removing that directory.
    public let url: URL
    public let byteCount: Int
    /// False for a handle to a file the engine did not write, which it must never
    /// remove either.
    private let ownsFile: Bool
    private let lock = NSLock()
    private var isDiscarded = false

    init(url: URL, byteCount: Int, ownsFile: Bool = true) {
        self.url = url
        self.byteCount = byteCount
        self.ownsFile = ownsFile
    }

    /// A record of a file the engine did not write. Discarding it does nothing, which
    /// is what a SwiftUI preview of the finished sheet needs.
    public static func unowned(_ url: URL, byteCount: Int) -> ExportedFile {
        ExportedFile(url: url, byteCount: byteCount, ownsFile: false)
    }

    /// Removes the file and the directory holding it. Idempotent.
    public func discard() {
        lock.lock()
        let already = isDiscarded
        isDiscarded = true
        lock.unlock()
        guard !already, ownsFile else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    deinit { discard() }

    public static func == (lhs: ExportedFile, rhs: ExportedFile) -> Bool { lhs === rhs }

    /// Where an Export writes unless a caller says otherwise. The temporary directory
    /// is inside the sandbox, is excluded from backup, and is not reachable from the
    /// Files app, which is what makes it the right place for a file this short-lived.
    public static var temporaryRoot: URL { FileManager.default.temporaryDirectory }

    /// Removes exports left behind by an earlier version, which deleted a file only
    /// when an Export was cancelled or its save failed. Cheap enough for launch: it
    /// is one directory listing.
    ///
    /// Only entries whose names are the pattern the app itself generates — a bare
    /// UUID — are removed. A sweep that guessed more widely would be destructive
    /// beyond its own scope, and the temporary directory is not exclusively ours.
    public static func sweepLeftovers(in directory: URL = ExportedFile.temporaryRoot) {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for entry in entries where UUID(uuidString: entry.lastPathComponent) != nil {
            try? manager.removeItem(at: entry)
        }
    }
}

extension ExportedFile: Equatable {}

/// Writes an Export to a file the engine owns.
enum ExportStore {
    static func write(_ data: Data, named name: String, in root: URL) throws -> ExportedFile {
        let manager = FileManager.default
        let directory = root.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        // The strongest protection the platform offers, so a copy of a photograph
        // sitting on disk is unreadable whenever the device is locked rather than
        // merely before first unlock. Revisit this if a background Export is ever
        // added: that protection level and background work are in tension.
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtection)
        #endif
        do { try data.write(to: url, options: options) }
        catch {
            try? manager.removeItem(at: directory)
            throw error
        }
        return ExportedFile(url: url, byteCount: data.count)
    }

    /// A filename component built from a Profile id. Every id in the Catalogue is
    /// already a lowercase slug and `FilmProfile.validate()` now requires one, but a
    /// filename must not depend on that staying true — the moment a Profile can be
    /// imported, an id is attacker-chosen and `appendingPathComponent` accepts `../`
    /// without complaint.
    static func fileName(_ stem: String, extension fileExtension: String) -> String {
        let allowed = stem.map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
                ? character : "-"
        }
        let slug = String(allowed.prefix(64))
        return "\(slug.isEmpty ? "export" : slug).\(fileExtension)"
    }
}
