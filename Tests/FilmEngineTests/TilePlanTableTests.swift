import Testing
import Foundation
import FilmEngine

// The Tile plan for a range of frame sizes, checked in as a table.
//
// The plan is arithmetic on the frame's dimensions and the Profile's reach, so it can
// be asserted without decoding a frame or rendering a pixel. It is written down here
// rather than derived in the assertions because the defect it guards against is a
// *cliff*: the Scattering Pyramid gains a level the moment Bloom's sigma passes a
// threshold, the Apron the Passes ask for roughly doubles, and a fixed Tile budget can
// no longer afford it. A table makes that visible as a diff instead of a slow export.

private func cinestill() throws -> Profile {
    try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "cinestill-800t" })
}

/// One row of the table: what a frame of this size plans to.
private struct Row {
    let frame: (width: Int, height: Int)
    let apron: Int
    let requestedApron: Int
    let core: Int
    let padded: (width: Int, height: Int)
    let grid: (columns: Int, rows: Int)
}

/// The Catalogue's widest blur — Cinestill 800T at default settings — at the frame
/// sizes a photo library actually hands the Export. 4032 px is an iPhone HEIF, 6000 px
/// a 24MP import, 8064 px an iPhone 48MP ProRAW. 4480 and 4500 bracket the level the
/// pyramid gains at a long edge of about 4495 px, which is where the cliff is.
private let table: [Row] = [
    Row(frame: (4032, 3024), apron: 476, requestedApron: 476, core: 704,
        padded: (1664, 1680), grid: (6, 5)),
    Row(frame: (4480, 3360), apron: 476, requestedApron: 476, core: 704,
        padded: (1664, 1696), grid: (7, 5)),
    Row(frame: (4500, 3375), apron: 673, requestedApron: 956, core: 256,
        padded: (1684, 1711), grid: (18, 14)),
    Row(frame: (6000, 4000), apron: 673, requestedApron: 956, core: 256,
        padded: (1648, 1696), grid: (24, 16)),
    Row(frame: (8064, 6048), apron: 673, requestedApron: 956, core: 256,
        padded: (1664, 1696), grid: (32, 24)),
]

@Test func theTilePlanForEveryRepresentativeFrameSizeMatchesTheCheckedInTable() async throws {
    let renderer = try Renderer()
    let profile = try cinestill()
    for row in table {
        let plan = try await renderer.tilePlan(frameWidth: row.frame.width, frameHeight: row.frame.height,
                                               profile: profile)
        let size = "\(row.frame.width)x\(row.frame.height)"
        #expect(plan.apron == row.apron, "\(size) apron")
        #expect(plan.requestedApron == row.requestedApron, "\(size) requested Apron")
        #expect(plan.isApronCapped == (row.apron < row.requestedApron), "\(size) capped")
        #expect(plan.coreWidth == row.core && plan.coreHeight == row.core, "\(size) core")
        #expect(plan.paddedWidth == row.padded.width && plan.paddedHeight == row.padded.height, "\(size) padded")
        #expect(plan.columns == row.grid.columns && plan.rows == row.grid.rows, "\(size) grid")
    }
}

@Test func aCappedApronKeepsAtLeastHalfOfWhatThePassesAskedFor() async throws {
    // `docs/export.md` puts the threshold for a visible Tile Seam at about half the
    // full reach. An Apron capped below that spends the most work of any plan to
    // deliver the one result the plan itself judges defective.
    let renderer = try Renderer()
    let profile = try cinestill()
    for row in table {
        let plan = try await renderer.tilePlan(frameWidth: row.frame.width, frameHeight: row.frame.height,
                                               profile: profile)
        guard plan.isApronCapped else { continue }
        #expect(Double(plan.apron) >= 0.5 * Double(plan.requestedApron),
                "\(row.frame.width)x\(row.frame.height) Apron \(plan.apron) of \(plan.requestedApron)")
    }
}

@Test func aTilePlanNeverSpendsMoreTileTextureBytesThanItsOptionsAllow() async throws {
    let renderer = try Renderer()
    let profile = try cinestill()
    for row in table {
        for budget in [160 << 20, 320 << 20, 640 << 20] {
            let plan = try await renderer.tilePlan(frameWidth: row.frame.width, frameHeight: row.frame.height,
                                                   profile: profile,
                                                   options: ExportOptions(textureBudgetBytes: budget))
            let bytes = plan.paddedWidth * plan.paddedHeight * 8 * TilePlan.tileTextureCount
            // A frame smaller than one Tile is rendered whole, which is the Preview's
            // own allocation rather than a Tile budget overrun.
            guard !plan.isUntiled else { continue }
            #expect(bytes <= budget, "\(row.frame.width)x\(row.frame.height) at \(budget >> 20)MB spends \(bytes >> 20)MB")
        }
    }
}
