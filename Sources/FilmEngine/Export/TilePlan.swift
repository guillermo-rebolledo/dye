import Foundation

/// How the Export Render Path divides a frame into Tiles.
///
/// A 48MP frame at the pipeline's RGBA float16 is roughly 380MB per intermediate
/// texture and the graph holds a dozen of them at once, so the frame is rendered a
/// Tile at a time. Each Tile is rendered with an **Apron** — a margin sized to the
/// furthest any Pass reaches for a neighbouring pixel — which is discarded when the
/// Tile's core is written out. Without it, Halation crossing a Tile boundary reads
/// the edge of the Tile instead of the rest of the frame and leaves a **Tile Seam**.
///
/// Every Tile is rendered at the same padded size, so one set of textures serves the
/// whole Export. Tiles whose core sits against the frame edge slide their Apron
/// inward rather than shrinking, and the Apron that would fall outside the frame is
/// simply absent: the Pass then clamps at the frame edge, which is exactly what an
/// untiled render does there.
public struct TilePlan: Sendable, Equatable {
    public let frameWidth: Int
    public let frameHeight: Int
    /// Pixels of Apron on every side of a Tile that has room for one.
    public let apron: Int
    /// What the Passes asked for, before the memory budget had its say. Greater than
    /// `apron` when the widest blur in the pipeline reaches further than a Tile can
    /// afford to carry, which is when a Tile stops being an exact window onto the
    /// untiled render and starts being a very close one.
    public let requestedApron: Int
    public var isApronCapped: Bool { apron < requestedApron }
    /// What every Tile origin is a multiple of. The Scattering Pyramid's 2×2 average
    /// pairs texels from its texture's own origin, so two Tiles that start on different
    /// parities of that grid halve the same halo differently and their shared boundary
    /// shows the disagreement — an Apron alone does not prevent that.
    public let alignment: Int
    /// The region a Tile writes out.
    public let coreWidth: Int
    public let coreHeight: Int
    /// Core plus Apron, and the size every Tile is rendered at.
    public let paddedWidth: Int
    public let paddedHeight: Int
    public let columns: Int
    public let rows: Int
    public var count: Int { columns * rows }

    /// One unit of Export work: what is rendered, and the part of it that is kept.
    public struct Tile: Sendable, Equatable {
        /// The written-out core, in frame coordinates.
        public let x: Int, y: Int, width: Int, height: Int
        /// The rendered region's origin in frame coordinates. Grain and the Geometry
        /// Pass are given this so they read frame positions rather than Tile ones.
        public let originX: Int, originY: Int
        /// Where the core starts inside the rendered Tile.
        public var insetX: Int { x - originX }
        public var insetY: Int { y - originY }
    }

    /// - Parameters:
    ///   - apron: the furthest any Pass reaches, in pixels, from the render Plan.
    ///   - budgetBytes: how much the padded Tile's textures may occupy. The pipeline
    ///     holds both Scattering Pyramids, the MTF's three textures and the two
    ///     ping-pong textures, which comes to about fourteen Tile-sized allocations.
    ///   - minimumCore: a Tile smaller than this is more overhead than work; a wide
    ///     enough Apron grows the padded Tile past the budget rather than shrinking
    ///     the core below it, because a Tile Seam is a defect and memory is a target.
    public init(frameWidth: Int, frameHeight: Int, apron: Int, alignment: Int = 1,
                budgetBytes: Int = 320 << 20, minimumCore: Int = 256) throws {
        guard frameWidth > 0, frameHeight > 0, apron >= 0, minimumCore > 0, budgetBytes > 0,
              alignment > 0, alignment & (alignment - 1) == 0 else {
            throw FilmError.invalid("Invalid tiling parameters")
        }
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.alignment = alignment
        requestedApron = apron
        let bytesPerTilePixel = Self.tileTextureCount * 8
        // Less one alignment step, which is what holding every Tile origin on the
        // Scattering Pyramid's grid can add to the padded window below.
        let budgetEdge = max(1, Int(Double(budgetBytes / bytesPerTilePixel).squareRoot()) - alignment)
        // The Apron is most of what the budget buys, so it is what the budget has to
        // bound. A Tile is core plus Apron whatever the core is, so leaving the Apron
        // free and shrinking the core to compensate does not spend less memory — it
        // spends more, on more Tiles, and quietly overruns the figure it was given.
        // Where the widest blur reaches further than that allows, the Apron is capped
        // and the truncated tail is a fraction of a code value rather than a seam.
        self.apron = min(apron, max(0, (budgetEdge - minimumCore) / 2))
        let apron = self.apron
        // A core has to be a whole number of alignment steps, or the origins derived
        // from it cannot stay on the grid. Rounded down against the budget, so the
        // rounding does not spend memory the budget did not allow, and up against the
        // floor, because a Tile that small is more Apron than image either way.
        func aligned(_ value: Int, up: Bool) -> Int { (value + (up ? alignment - 1 : 0)) / alignment * alignment }
        let core = max(aligned(minimumCore, up: true), aligned(max(0, budgetEdge - 2 * apron), up: false))
        coreWidth = min(frameWidth, core)
        coreHeight = min(frameHeight, core)
        // The last Tile of a row starts at `frameWidth - paddedWidth`, so that has to
        // land on the grid too. Trimming the padded window by whole alignment steps
        // from the frame's own width is what puts it there, and it only ever makes the
        // window wider than the Apron asked for.
        paddedWidth = Self.padded(frame: frameWidth, core: coreWidth, apron: apron, alignment: alignment)
        paddedHeight = Self.padded(frame: frameHeight, core: coreHeight, apron: apron, alignment: alignment)
        columns = (frameWidth + coreWidth - 1) / coreWidth
        rows = (frameHeight + coreHeight - 1) / coreHeight
    }

    private static func padded(frame: Int, core: Int, apron: Int, alignment: Int) -> Int {
        let wanted = min(frame, core + 2 * apron)
        return frame - (frame - wanted) / alignment * alignment
    }

    /// RGBA float16 textures the pass graph holds at Tile size at once: the two
    /// ping-pong textures, three for the MTF Pass, and a Scattering Pyramid each for
    /// Bloom and Halation — a raw extract plus levels and scratch, which sum to about
    /// eight thirds of a Tile once the halving is counted.
    static let tileTextureCount = 14

    public func tile(_ index: Int) -> Tile {
        precondition((0..<count).contains(index), "Tile index out of range")
        let x = (index % columns) * coreWidth
        let y = (index / columns) * coreHeight
        // Rounding the Apron's start *down* to the grid only ever gives the Tile more
        // margin than it needs, and both bounds it is clamped to are already on it.
        func origin(_ start: Int, frame: Int, padded: Int) -> Int {
            min(max((start - apron) / alignment * alignment, 0), frame - padded)
        }
        return Tile(x: x, y: y, width: min(coreWidth, frameWidth - x), height: min(coreHeight, frameHeight - y),
                    originX: origin(x, frame: frameWidth, padded: paddedWidth),
                    originY: origin(y, frame: frameHeight, padded: paddedHeight))
    }

    /// True when the frame fits in one Tile, so the Export path renders it exactly as
    /// the Preview path would.
    public var isUntiled: Bool { count == 1 && paddedWidth == frameWidth && paddedHeight == frameHeight }
}
