import Foundation
import FilmEngine

/// The black & white branch's numerical gate, in two stages.
///
/// `measured-density` is the Step Wedge proper: a synthetic ramp fed through the
/// public renderer with the scan disabled, read back in Density Space and compared
/// against the digitised Characteristic Curve. Because the collapse's weights are
/// normalised, a neutral of linear value `10^logH` reaches the Density Curve at
/// exactly `logH`, so the ramp is written in the datasheet's own physical exposure.
///
/// `filter-factor` is the evidence that the Spectral Weights are the Stock's own and
/// not a luminance weighting wearing five hats. Kodak publishes a daylight filter
/// factor per Wratten filter *per film*, and those tables differ between Tri-X and
/// T-Max. The factor falls straight out of the derived weights as the ratio of their
/// sums, so comparing it to the published table checks the integration against a
/// number nobody involved chose. It does not validate the artistic transmittance
/// model; see the Curve Sets' SOURCES.md for what each residual is and is not.
func monochromeStepWedge(curves: CurveSet, profile: Profile) async throws -> [StepWedgeRow] {
    let model = try MonochromeSpectralModel(curves: curves)
    let renderer = try Renderer()
    var samples = model.curve.points.map { ($0.logExposure, $0.density) }
    samples += zip(model.curve.points, model.curve.points.dropFirst()).map {
        (($0.logExposure + $1.logExposure) / 2, ($0.density + $1.density) / 2)
    }
    samples.sort { $0.0 < $1.0 }
    let pixels = samples.flatMap { logH, _ -> [Float16] in
        let light = Float16(0.18 * pow(10, logH - model.shaper.middleGrayLogExposure))
        return [light, light, light, 1]
    }
    let rendered = try await renderer.render(image: .linear(try LinearImage(width: samples.count, height: 1, rgba: pixels)),
        profile: profile, settings: wedgeSettings(balancedFor: profile, outputStage: OutputStage.none))
    var rows = samples.enumerated().map { index, sample in
        StepWedgeRow(stage: .measuredDensity, developmentOffset: 0, channel: 0, logExposure: sample.0,
                     reference: sample.1, rendered: Double(rendered.rgba[index * 4]))
    }
    // Compared in stops rather than as a bare ratio: a filter factor is an exposure
    // correction, and half a stop means the same thing at 1.5 as it does at 8.
    let published = try curves.publishedFilterFactors()
    guard let monochrome = profile.metadata.monochrome else {
        throw FilmError.invalid("Profile \(profile.id) has no Monochrome Collapse to filter")
    }
    for (index, filter) in MonochromeSpectralModel.contrastFilters.enumerated() {
        guard let derived = monochrome.filterFactorStops(filter), let reference = published[filter] else {
            throw FilmError.invalid("Profile \(profile.id) has no \(filter.rawValue) Contrast Filter")
        }
        rows.append(StepWedgeRow(stage: .filterFactor, developmentOffset: 0, channel: index,
                                 logExposure: Double(index), reference: log2(reference), rendered: derived))
    }
    return rows
}
