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

/// The table is a claim about the planner, not about the machine running it, so it
/// pins the budget rather than reading the device's.
private let fixedBudget = ExportOptions(textureBudgetBytes: ExportOptions.minimumTextureBudgetBytes)

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
    Row(frame: (4032, 3024), apron: 476, requestedApron: 476, core: 1088,
        padded: (2048, 2064), grid: (4, 3)),        // 12 Tiles, 4.2x overdraw
    Row(frame: (4480, 3360), apron: 476, requestedApron: 476, core: 1088,
        padded: (2048, 2080), grid: (5, 4)),        // 20 Tiles, 5.7x overdraw
    Row(frame: (4500, 3375), apron: 676, requestedApron: 956, core: 640,
        padded: (2068, 2095), grid: (8, 6)),        // 48 Tiles, 13.7x overdraw
    Row(frame: (6000, 4000), apron: 676, requestedApron: 956, core: 640,
        padded: (2032, 2080), grid: (10, 7)),       // 70 Tiles, 12.3x overdraw
    Row(frame: (8064, 6048), apron: 676, requestedApron: 956, core: 640,
        padded: (2048, 2080), grid: (13, 10)),      // 130 Tiles, 11.3x overdraw
]

@Test func theTilePlanForEveryRepresentativeFrameSizeMatchesTheCheckedInTable() async throws {
    let renderer = try Renderer()
    let profile = try cinestill()
    for row in table {
        let plan = try await renderer.tilePlan(frameWidth: row.frame.width, frameHeight: row.frame.height,
                                               profile: profile, options: fixedBudget)
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
                                               profile: profile, options: fixedBudget)
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

@Test func theTileTextureBudgetCountsWhatTheRendererActuallyHolds() async throws {
    // `TilePlan.tileTextureCount` divides the Export's memory budget, so a graph that
    // grew a texture since the constant was written would overrun the budget silently.
    // The claim is checked against the Renderer's own retained scratch rather than
    // against the comment beside the constant.
    let renderer = try Renderer()
    let profile = try cinestill()
    // The stress case: the widest Halation in the Catalogue at the top of its control,
    // which is the deepest Scattering Pyramid a frame this size resolves to.
    let settings = RenderSettings(temperatureKelvin: 3200, halationIntensity: 2)
    var worst = 0.0
    for size in [512, 1024, 1536] {
        var rgba = [Float16](repeating: 0.18, count: size * size * 4)
        for index in stride(from: 3, to: rgba.count, by: 4) { rgba[index] = 1 }
        let image = try LinearImage(width: size, height: size, rgba: rgba)
        _ = try await renderer.render(image: .linear(image), profile: profile, settings: settings)
        let held = await renderer.retainedTileTextureBytes
        worst = max(worst, Double(held) / Double(size * size * 8))
    }
    #expect(worst <= Double(TilePlan.tileTextureCount))
    // And not wildly under it either: a budget divided by a figure much larger than
    // the truth plans more, smaller Tiles than the memory it was given calls for.
    #expect(worst >= 0.8 * Double(TilePlan.tileTextureCount))
}

@Test func bloomAndHalationShareOneScatteringPyramidAndAWarmRendererReallocatesNothing() async throws {
    let renderer = try Renderer()
    let profile = try cinestill()
    let settings = RenderSettings(temperatureKelvin: 3200, halationIntensity: 2)
    let size = 512
    var rgba = [Float16](repeating: 0.18, count: size * size * 4)
    for index in stride(from: 3, to: rgba.count, by: 4) { rgba[index] = 1 }
    let image = try LinearImage(width: size, height: size, rgba: rgba)
    _ = try await renderer.render(image: .linear(image), profile: profile, settings: settings)
    // Cold: the ping-pong pair, one pyramid and the MTF trio — three allocations, and
    // not the four a pyramid each for Bloom and Halation would take.
    #expect(await renderer.renderCounters.tileTextureAllocations == 3)
    await renderer.resetRenderCounters()
    // Warm, and across the depth difference between the two Passes: Bloom resolves to
    // a deeper pyramid than Halation on the same frame, and re-entering at the shallower
    // depth must use a prefix of what is already allocated rather than replace it.
    for intensity in [1.0, 2.0, 0.5, 1.0] {
        var swept = settings
        swept.halationIntensity = intensity
        _ = try await renderer.render(image: .linear(image), profile: profile, settings: swept)
    }
    #expect(await renderer.renderCounters.tileTextureAllocations == 0)
}

@Test func aFrameTwiceTheSizeDoesNotCostFifteenTimesTheWork() async throws {
    // The headline gate. Overdraw is what the Export actually pays: every Tile runs
    // the whole Pass graph over its padded window to keep its core, so the rendered
    // pixels divided by the frame's is the multiplier on the Export's time.
    //
    // The bound below is what bounding the Apron by a share of the budget delivers,
    // not what the frame deserves. The Apron exists only so each Tile's *coarse*
    // pyramid levels agree with the untiled render's; those levels are a sixteenfold
    // downsample carrying no high-frequency content and could be built once per frame,
    // which would leave the Apron covering the fine levels alone and bring this to
    // about 1.6x. Until that lands this is the gate that keeps the cliff from
    // returning, and the number it holds is the number to tighten.
    let renderer = try Renderer()
    let profile = try cinestill()
    var previous = 0.0
    for row in table {
        let plan = try await renderer.tilePlan(frameWidth: row.frame.width, frameHeight: row.frame.height,
                                               profile: profile, options: fixedBudget)
        let rendered = Double(plan.count * plan.paddedWidth * plan.paddedHeight)
        let overdraw = rendered / Double(row.frame.width * row.frame.height)
        #expect(overdraw <= 14, "\(row.frame.width)x\(row.frame.height) renders \(overdraw)x its own pixels")
        // The cliff was a jump from 6.6x to 47.8x across a 20-pixel change in the long
        // edge. A step remains where the pyramid gains a level, but it is a step of
        // about 2.4x rather than 7.2x, and nothing below it now costs more than a
        // 48MP frame does.
        if previous > 0 { #expect(overdraw <= 3 * previous) }
        previous = overdraw
    }
    let largest = try await renderer.tilePlan(frameWidth: 8064, frameHeight: 6048, profile: profile,
                                              options: fixedBudget)
    #expect(largest.count <= 160)
    // The core is a Tile's worth of image rather than the floor the old bound forced
    // it to. A 256-px core inside a 1664-px window keeps 2.4% of what it rendered.
    #expect(largest.coreWidth > 2 * fixedBudget.minimumTileEdge)
}

@Test func theTileBudgetFollowsTheDeviceRatherThanOneFigureForEveryPhone() async throws {
    // The floor is what every device was given before the budget was allowed to vary,
    // so scaling can only ever help; the ceiling is where a larger budget stops buying
    // a Tile and only costs resident texture.
    let budget = ExportOptions.deviceTextureBudgetBytes
    #expect(budget >= ExportOptions.minimumTextureBudgetBytes)
    #expect(budget <= ExportOptions.maximumTextureBudgetBytes)
    #expect(ExportOptions().resolvedTextureBudgetBytes == budget)
    #expect(ExportOptions(textureBudgetBytes: 64 << 20).resolvedTextureBudgetBytes == 64 << 20)

    // And more memory buys a better plan rather than merely a different one: a larger
    // budget is never more Tiles, and at the top of the range the 48MP frame carries
    // the whole Apron the Passes asked for.
    let renderer = try Renderer()
    let profile = try cinestill()
    var counts: [Int] = []
    for bytes in [ExportOptions.minimumTextureBudgetBytes, 640 << 20, ExportOptions.maximumTextureBudgetBytes] {
        let plan = try await renderer.tilePlan(frameWidth: 8064, frameHeight: 6048, profile: profile,
                                               options: ExportOptions(textureBudgetBytes: bytes))
        counts.append(plan.count)
    }
    #expect(zip(counts, counts.dropFirst()).allSatisfy { $0 >= $1 })
    let generous = try await renderer.tilePlan(frameWidth: 8064, frameHeight: 6048, profile: profile,
                                               options: ExportOptions(textureBudgetBytes: ExportOptions.maximumTextureBudgetBytes))
    #expect(!generous.isApronCapped)
}

@Test func theRenderPlanIsBuiltOncePerExportRatherThanOncePerTile() async throws {
    // A Plan resolves the Stock against the frame: it fits the Profile's MTF with two
    // Gaussians, builds the Grain Density Response table, splits the Scattering radii
    // across pyramid levels and reads up to four Colour Cubes. All of it depends on
    // the frame, none of it on which Tile of the frame is being rendered — the Plan's
    // own doc comment says so — so an Export that rebuilds it per Tile pays for the
    // same answer as many times as the frame divides.
    let renderer = try Renderer()
    let profile = try cinestill()
    let size = 384
    var rgba = [Float16](repeating: 0.2, count: size * size * 4)
    for index in stride(from: 3, to: rgba.count, by: 4) { rgba[index] = 1 }
    let image = try LinearImage(width: size, height: size, rgba: rgba)
    let settings = RenderSettings(temperatureKelvin: 3200, halationIntensity: 2)
    // A budget small enough to put several Tiles across a small frame, which is the
    // only reason a test frame is tiled at all.
    let options = ExportOptions(textureBudgetBytes: 96 * 96 * 8 * TilePlan.tileTextureCount,
                                minimumTileEdge: 16, thermalState: .nominal)
    let plan = try await renderer.tilePlan(image: .linear(image), profile: profile,
                                           settings: settings, options: options)
    #expect(plan.count >= 9)
    await renderer.resetRenderCounters()
    _ = try await renderer.export(image: .linear(image), profile: profile, settings: settings,
                                  format: .jpeg, options: options)
    let built = await renderer.renderCounters.plansBuilt
    #expect(built == 1, "\(plan.count) Tiles built \(built) Plans")

    // One at a second budget too, because the figure that must not move with the Tile
    // count is the one under test. A Tile is consulted about exactly one thing — how
    // deep a Scattering Pyramid fits in it — so a Tile too small to carry the depth the
    // frame resolved to would cost a second Plan; that is still once for the Export
    // rather than once per Tile, and it is not a case a photograph reaches, since the
    // padded Tile of a 48MP frame is over two thousand pixels against nine levels.
    let larger = ExportOptions(textureBudgetBytes: 192 * 192 * 8 * TilePlan.tileTextureCount,
                               minimumTileEdge: 16, thermalState: .nominal)
    let largerPlan = try await renderer.tilePlan(image: .linear(image), profile: profile,
                                                 settings: settings, options: larger)
    #expect(largerPlan.count > 1 && largerPlan.count < plan.count)
    await renderer.resetRenderCounters()
    _ = try await renderer.export(image: .linear(image), profile: profile, settings: settings,
                                  format: .jpeg, options: larger)
    #expect(await renderer.renderCounters.plansBuilt == 1)
}
