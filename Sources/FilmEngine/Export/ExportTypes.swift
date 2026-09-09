import Foundation
import UniformTypeIdentifiers

/// The two Render Paths. They run identical shaders and differ in how much of the
/// frame is in flight at once, which is the only thing a Pass may key off.
public enum RenderPath: Sendable, Equatable { case preview, export }

/// The file an Export is written as.
public enum ExportFormat: String, Sendable, CaseIterable, Identifiable {
    /// Modern, small, and what the camera already writes. Eight bits per channel.
    case heif
    /// Eight bits per channel, for anything that cannot read HEIF.
    case jpeg
    /// Sixteen bits per channel: the reason to pick it is to keep more than a
    /// display can show, so an eight-bit TIFF would defeat the point.
    case tiff

    public var id: String { rawValue }
    public var displayName: String {
        switch self { case .heif: "HEIF"; case .jpeg: "JPEG"; case .tiff: "TIFF" }
    }
    public var bitsPerComponent: Int { self == .tiff ? 16 : 8 }
    public var fileExtension: String {
        switch self { case .heif: "heic"; case .jpeg: "jpg"; case .tiff: "tiff" }
    }
    public var contentType: UTType {
        switch self { case .heif: .heic; case .jpeg: .jpeg; case .tiff: .tiff }
    }
    /// Whether the writer's quality setting means anything for this container.
    public var isLossy: Bool { self != .tiff }
}

/// How far through a tiled Export the renderer is. Reported per Tile, which is the
/// granularity at which the work is also cancellable.
public struct ExportProgress: Sendable, Equatable {
    public let completedTiles: Int
    public let tileCount: Int
    public var fraction: Double { tileCount > 0 ? Double(completedTiles) / Double(tileCount) : 1 }
    public init(completedTiles: Int, tileCount: Int) {
        self.completedTiles = completedTiles
        self.tileCount = tileCount
    }
}

/// What the Export path is allowed to spend, and what the device can currently
/// afford. Defaults suit a 48MP frame on a phone.
public struct ExportOptions: Sendable, Equatable {
    /// Bytes the padded Tile's textures may occupy. Smaller means more, smaller
    /// Tiles: the same result, more Apron overhead, less peak memory.
    public var textureBudgetBytes: Int
    /// A Tile smaller than this is more Apron than image.
    public var minimumTileEdge: Int
    /// Nil reads the device's state when the Export starts. Fixing it is what makes
    /// the thermal behaviour testable.
    public var thermalState: ProcessInfo.ThermalState?
    /// Optional capture date embedded in the exported image.
    public var creationDate: Date?
    /// Encoder quality for the lossy containers, 0...1.
    public var quality: Double
    /// The share of the Scattering Passes' own reach the Apron carries, 0...1.
    ///
    /// Every blur in the pipeline is a truncated kernel, so the reach a Tile would
    /// have to carry to be *exactly* a window onto the untiled render is finite — but
    /// it is around seven sigmas of the coarsest pyramid level in play, and paying it
    /// in full costs a 12MP Export roughly six times its render time. The default
    /// keeps a little over half of it, which on the Catalogue's stress case — a point
    /// light ten stops over white through Cinestill 800T at 200% halation — leaves the
    /// tiled and untiled renders apart by four hundredths of an eight-bit code value.
    /// One buys exactness; below about a half, the truncation starts to be a seam.
    public var apronFraction: Double

    public init(textureBudgetBytes: Int = 320 << 20, minimumTileEdge: Int = 256,
                thermalState: ProcessInfo.ThermalState? = nil, quality: Double = 0.9,
                apronFraction: Double = 0.6, creationDate: Date? = nil) {
        self.textureBudgetBytes = textureBudgetBytes
        self.minimumTileEdge = minimumTileEdge
        self.thermalState = thermalState
        self.creationDate = creationDate
        self.quality = quality
        self.apronFraction = apronFraction
    }

    var resolvedThermalState: ProcessInfo.ThermalState { thermalState ?? ProcessInfo.processInfo.thermalState }
}

extension ProcessInfo.ThermalState {
    /// At `.serious` the system is already throttling the GPU. Continuing to ask for
    /// the expensive work makes the export slower *and* the device hotter, so the
    /// engine gives something up instead.
    var isThrottling: Bool { self == .serious || self == .critical }
}
