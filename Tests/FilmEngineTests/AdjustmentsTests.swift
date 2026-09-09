import Testing
import Foundation
import FilmEngine

/// The Adjustment Pass: a photo editor's tone and colour controls, applied to the
/// scan after the Output Stage and asserted through the renderer entry point.
@Suite struct AdjustmentsTests {
    private func render(_ renderer: Renderer, _ rgb: [Double], profile: Profile = .identity,
                        adjustments: Adjustments) async throws -> [Float] {
        var rgba: [Float16] = []
        for pixel in stride(from: 0, to: rgb.count, by: 3) {
            rgba += [Float16(rgb[pixel]), Float16(rgb[pixel + 1]), Float16(rgb[pixel + 2]), 1]
        }
        let image = try LinearImage(width: rgb.count / 3, height: 1, rgba: rgba)
        let result = try await renderer.render(image: .linear(image), profile: profile,
                                               settings: RenderSettings(output: .workingSpace, adjustments: adjustments))
        return result.rgba.map(Float.init)
    }

    private func grey(_ renderer: Renderer, _ values: [Double], _ adjustments: Adjustments) async throws -> [Float] {
        let rendered = try await render(renderer, values.flatMap { [$0, $0, $0] }, adjustments: adjustments)
        return stride(from: 0, to: rendered.count, by: 4).map { rendered[$0] }
    }

    @Test func neutralAdjustmentsAreAnExactPassThrough() async throws {
        #expect(Adjustments().isNeutral)
        #expect(RenderSettings().adjustments == Adjustments())
        #expect(!Adjustments(vibrance: 0.01).isNeutral)
        let renderer = try Renderer()
        let input: [Double] = [0.25, 0.5, 0.125, -0.5, 4, 0, 0.18, 0.18, 0.18]
        let out = try await render(renderer, input, adjustments: Adjustments())
        let expected = [0.25, 0.5, 0.125, 1, -0.5, 4, 0, 1, 0.18, 0.18, 0.18, 1].map { Float(Float16($0)) }
        #expect(out == expected)
    }

    @Test func eachToneControlMovesTheTonesItNamesAndHoldsTheOthers() async throws {
        let renderer = try Renderer()
        let wedge: [Double] = [0, 0.005, 0.02, 0.18, 0.5, 1, 2]
        let plain = try await grey(renderer, wedge, Adjustments())

        // Shadows open the darks, leave black and white where they are and barely
        // reach a highlight.
        let shadows = try await grey(renderer, wedge, Adjustments(shadows: 1))
        #expect(shadows[0] == 0 && shadows[5] == 1)
        #expect(shadows[2] > plain[2] * 1.5)
        #expect(shadows[4] / plain[4] < shadows[2] / plain[2])
        let closed = try await grey(renderer, wedge, Adjustments(shadows: -1))
        #expect(closed[2] < plain[2] && closed[0] == 0)

        // Highlight recovery brings light from past white back under it and does not
        // touch mid-grey; pushing lifts the brights and leaves white alone.
        let recovered = try await grey(renderer, wedge, Adjustments(highlights: -1))
        #expect(recovered[6] < 1 && recovered[6] > recovered[5])
        #expect(recovered[5] < 1 && recovered[5] > 0.5)
        #expect(recovered[3] == plain[3])
        let pushed = try await grey(renderer, wedge, Adjustments(highlights: 1))
        #expect(pushed[4] > plain[4] && pushed[5] == 1)
        #expect(pushed[2] - plain[2] < pushed[4] - plain[4])

        // Contrast pulls the darks down and the brights up about the middle, with
        // black and white held.
        let contrast = try await grey(renderer, wedge, Adjustments(contrast: 1))
        #expect(contrast[2] < plain[2] && contrast[4] > plain[4])
        #expect(contrast[0] == 0 && contrast[5] == 1)
        let flat = try await grey(renderer, wedge, Adjustments(contrast: -1))
        #expect(flat[2] > plain[2] && flat[4] < plain[4])

        // Brightness lifts the midtones with the ends held.
        let bright = try await grey(renderer, wedge, Adjustments(brightness: 1))
        #expect(bright[3] > plain[3] && bright[0] == 0 && bright[5] == 1)
        let dim = try await grey(renderer, wedge, Adjustments(brightness: -1))
        #expect(dim[3] < plain[3])

        // Black point: positive crushes the deepest tones into black itself, never
        // below it; negative lifts black to a matte grey.
        let deep = try await grey(renderer, wedge, Adjustments(blackPoint: 1))
        #expect(deep[1] == 0 && deep[0] == 0)
        #expect(deep[4] < plain[4] && deep[4] > 0.35)
        let matte = try await grey(renderer, wedge, Adjustments(blackPoint: -1))
        #expect(matte[0] > 0.01 && matte[0] < 0.05)
    }

    @Test func brillianceIsShadowsHighlightsAndContrastMadeTogether() async throws {
        let renderer = try Renderer()
        let input: [Double] = [0.02, 0.03, 0.05, 0.18, 0.18, 0.18, 0.7, 0.5, 0.3, 1.5, 1.2, 0.9]
        let brilliance = try await render(renderer, input, adjustments: Adjustments(brilliance: 1))
        let composed = try await render(renderer, input, adjustments: Adjustments(highlights: -0.5, shadows: 0.6, contrast: 0.3))
        #expect(brilliance == composed)
        // Detail comes forward: the dark end rises and the light end comes down.
        let plain = try await render(renderer, input, adjustments: Adjustments())
        #expect(brilliance[0] > plain[0] && brilliance[8] < plain[8])
    }

    @Test func theToneCurveStaysMonotoneAtEveryExtreme() async throws {
        let renderer = try Renderer()
        let ramp = (0...255).map { Double($0) / 255 * 2 }
        let extremes = [
            Adjustments(brilliance: 1, highlights: 1, shadows: 1, contrast: 1, brightness: 1, blackPoint: 1),
            Adjustments(brilliance: -1, highlights: -1, shadows: -1, contrast: -1, brightness: -1, blackPoint: -1),
            Adjustments(brilliance: 1, highlights: -1, shadows: 1, contrast: -1, brightness: 1, blackPoint: -1),
            Adjustments(brilliance: -1, highlights: 1, shadows: -1, contrast: 1, brightness: -1, blackPoint: 1),
        ]
        for adjustments in extremes {
            let out = try await grey(renderer, ramp, adjustments)
            for i in 1..<out.count { #expect(out[i] >= out[i - 1], "\(adjustments) at \(i)") }
            let finite = out.allSatisfy { $0.isFinite }
            #expect(finite)
        }
    }

    @Test func saturationScalesChromaAboutLuminanceAndVibranceFavoursTheMuted() async throws {
        let renderer = try Renderer()
        let muted: [Double] = [0.2, 0.22, 0.3], vivid: [Double] = [0.02, 0.05, 0.5]
        let skin: [Double] = [0.5, 0.3, 0.2], leaf: [Double] = [0.2, 0.5, 0.3]
        func luminance(_ c: [Float]) -> Float { 0.2627 * c[0] + 0.678 * c[1] + 0.0593 * c[2] }
        func chroma(_ c: [Float]) -> Float { (c.max()! - c.min()!) }

        let plain = try await render(renderer, muted + vivid, adjustments: Adjustments())
        let grey = try await render(renderer, muted + vivid, adjustments: Adjustments(saturation: -1))
        for pixel in 0..<2 {
            let c = Array(grey[pixel * 4..<pixel * 4 + 3]), original = Array(plain[pixel * 4..<pixel * 4 + 3])
            #expect(abs(c[0] - c[1]) < 0.002 && abs(c[1] - c[2]) < 0.002)
            #expect(abs(luminance(c) - luminance(original)) < 0.003)
        }
        let doubled = try await render(renderer, muted + vivid, adjustments: Adjustments(saturation: 1))
        #expect(abs(chroma(Array(doubled[0..<3])) - 2 * chroma(Array(plain[0..<3]))) < 0.005)

        // A boost reaches the muted colour more than the vivid one, protects skin, and
        // a cut is a plain desaturation.
        let vibrant = try await render(renderer, muted + vivid + skin + leaf, adjustments: Adjustments(vibrance: 1))
        let before = try await render(renderer, muted + vivid + skin + leaf, adjustments: Adjustments())
        func gain(_ pixel: Int) -> Float {
            chroma(Array(vibrant[pixel * 4..<pixel * 4 + 3])) / chroma(Array(before[pixel * 4..<pixel * 4 + 3]))
        }
        #expect(gain(0) > gain(1) && gain(1) > 1)
        #expect(gain(2) < gain(3))
        let cut = try await render(renderer, muted + vivid, adjustments: Adjustments(vibrance: -1))
        #expect(cut == grey)
    }

    @Test func theAdjustmentPassFollowsTheScanAndPrecedesTheGeometry() async throws {
        let renderer = try Renderer()
        let portra = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "portra-400" })
        // Through a real Stock the controls act on the scan, not the light: a black
        // point lift raises the scan's black, which the film alone would leave at zero.
        let pixel = try LinearImage(width: 1, height: 1, rgba: [0, 0, 0, 1])
        let scanned = try await renderer.render(image: .linear(pixel), profile: portra, settings: .init(output: .workingSpace))
        let lifted = try await renderer.render(image: .linear(pixel), profile: portra,
                                               settings: .init(output: .workingSpace, adjustments: Adjustments(blackPoint: -1)))
        #expect(scanned.rgba[0] == 0 && lifted.rgba[0] > 0.01)
        // The Frame Border is drawn afterwards, so the rebate stays unexposed under
        // the same lift: the frame is adjusted, the film around it is not.
        let size = 64
        let frame = try LinearImage(width: size, height: size, rgba: [Float16](repeating: 0.5, count: size * size * 4))
        let bordered = try await renderer.render(image: .linear(frame), profile: .identity,
                                                 settings: .init(output: .workingSpace, frameBorder: 1, adjustments: Adjustments(blackPoint: -1)))
        let corner = 0, centre = (size / 2 * size + size / 2) * 4
        #expect(bordered.rgba[corner] == 0)
        #expect(bordered.rgba[centre] > 0.5)
    }

    @Test func adjustmentsSurviveAPresetAndAreMissingFromAnOldOne() throws {
        var settings = RenderSettings(exposureStops: 0.5)
        settings.adjustments = Adjustments(brilliance: 0.25, highlights: -0.5, shadows: 0.3, contrast: 0.1,
                                           brightness: -0.2, blackPoint: 0.15, saturation: 0.4, vibrance: -0.35)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(RenderSettings.self, from: data) == settings)
        // A Preset written before the Pass existed has no key, and reads as untouched.
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["adjustments"] = nil
        let old = try JSONDecoder().decode(RenderSettings.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.adjustments.isNeutral && old.exposureStops == 0.5)
        // So does one that names only some of the controls.
        let partial = try JSONDecoder().decode(Adjustments.self, from: Data(#"{"contrast": 0.5}"#.utf8))
        #expect(partial == Adjustments(contrast: 0.5))
        // The range is the type's own and is enforced with the rest of the settings.
        #expect(throws: FilmError.self) { try RenderSettings(adjustments: Adjustments(saturation: 1.5)).validate() }
        #expect(throws: FilmError.self) { try RenderSettings(adjustments: Adjustments(blackPoint: .nan)).validate() }
        try RenderSettings(adjustments: Adjustments(blackPoint: -1, vibrance: 1)).validate()
    }

    @Test func anExportedLUTCarriesTheAdjustmentsAndSaysSo() async throws {
        let renderer = try Renderer()
        let portra = try #require(ProfileCatalogue.bundled().profiles.first { $0.id == "portra-400" })
        let plain = RenderSettings(output: .displayP3, halationIntensity: 0, bloomIntensity: 0, grainIntensity: 0)
        var adjusted = plain
        adjusted.adjustments = Adjustments(contrast: 0.5, saturation: -0.3)
        let neutralLUT = try await renderer.exportedLUT(profile: portra, settings: plain)
        let adjustedLUT = try await renderer.exportedLUT(profile: portra, settings: adjusted)
        #expect(!neutralLUT.contains("adjusted") && adjustedLUT.contains("adjusted"))
        #expect(neutralLUT != adjustedLUT)
        // The cube is rendered through the same Pass the photo is: one mid-grey
        // address lands where the render puts it.
        let pixel = try LinearImage(width: 1, height: 1, rgba: [0.18, 0.18, 0.18, 1])
        let rendered = try await renderer.render(image: .linear(pixel), profile: portra, settings: adjusted)
        let address = try await renderer.render(image: .linear(pixel), profile: .identity, settings: .init(output: .displayP3))
        let size = 33
        let lines = adjustedLUT.split(separator: "\n").filter { $0.first?.isNumber == true }
        let index = (0..<3).map { Int((Double(address.rgba[$0]) * Double(size - 1)).rounded()) }
        let entry = lines[index[0] + size * (index[1] + size * index[2])].split(separator: " ").map { Double($0)! }
        for channel in 0..<3 { #expect(abs(entry[channel] - Double(rendered.rgba[channel])) < 0.03) }
    }
}
