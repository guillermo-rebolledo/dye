import SwiftUI
import UIKit
import FilmEngine

/// The design vocabulary every other file in the editor draws from: colour, type,
/// metric and motion. No file outside `FilmApp/Design/` should contain a colour,
/// a font size, a radius or a shadow. When a value is missing, add it here.
///
/// Colour is written the way the handoff writes it — sRGB hex for the greys,
/// Oklch for the accent, the process colours and the reds — and resolved to
/// Display P3 at the point of use. Every token below lands inside the sRGB gamut,
/// so the wider space costs nothing today and leaves the accent room to stay
/// itself on a P3 display.
enum Tokens {}

// MARK: - Colour

extension Tokens {
    /// A colour held in linear-light sRGB, whatever notation it was written in.
    /// Components may sit outside `0...1` here; they clamp only when resolved.
    struct Colour: Sendable, Equatable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double = 1

        /// An sRGB hex triplet, as the handoff's colour table writes it.
        static func hex(_ value: UInt32, alpha: Double = 1) -> Colour {
            func channel(_ shift: UInt32) -> Double {
                ColourMath.linearise(Double((value >> shift) & 0xFF) / 255)
            }
            return Colour(red: channel(16), green: channel(8), blue: channel(0), alpha: alpha)
        }

        /// Oklch, as the handoff writes the accent and the process colours:
        /// lightness `0...1`, chroma, hue in degrees.
        static func oklch(_ lightness: Double, _ chroma: Double, _ hue: Double, alpha: Double = 1) -> Colour {
            let (r, g, b) = ColourMath.oklchToLinearSRGB(lightness, chroma, hue)
            return Colour(red: r, green: g, blue: b, alpha: alpha)
        }

        func opacity(_ factor: Double) -> Colour {
            Colour(red: red, green: green, blue: blue, alpha: alpha * factor)
        }

        /// Gamma-encoded Display P3 components, clamped into the gamut.
        var displayP3: (red: Double, green: Double, blue: Double) {
            let (r, g, b) = ColourMath.linearSRGBToLinearDisplayP3(red, green, blue)
            return (ColourMath.encode(r), ColourMath.encode(g), ColourMath.encode(b))
        }

        var color: Color {
            let p3 = displayP3
            return Color(.displayP3, red: p3.red, green: p3.green, blue: p3.blue, opacity: alpha)
        }

        var uiColor: UIColor {
            let p3 = displayP3
            return UIColor(displayP3Red: p3.red, green: p3.green, blue: p3.blue, alpha: alpha)
        }
    }

    /// Colour space arithmetic, kept in one place so no token has to carry a
    /// hand-converted literal that can drift from the handoff's own notation.
    enum ColourMath {
        static func linearise(_ encoded: Double) -> Double {
            encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
        }

        static func encode(_ linear: Double) -> Double {
            let c = min(max(linear, 0), 1)
            return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        }

        static func oklchToLinearSRGB(_ lightness: Double, _ chroma: Double, _ hue: Double) -> (Double, Double, Double) {
            let radians = hue * .pi / 180
            let a = chroma * cos(radians)
            let b = chroma * sin(radians)
            let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
            let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
            let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
            return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        }

        /// sRGB and Display P3 share a white point and a transfer curve, so the
        /// conversion is one 3×3 through XYZ, folded into a single matrix here.
        static func linearSRGBToLinearDisplayP3(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
            (0.8224621 * r + 0.1775380 * g + 0.0000000 * b,
             0.0331941 * r + 0.9668058 * g + 0.0000000 * b,
             0.0170827 * r + 0.0723974 * g + 0.9105199 * b)
        }
    }
}

// MARK: - Palette

extension Tokens {
    /// The named colours. Light mode is specified only for the deck, the sheets
    /// and the ink (§13 of the handoff); the remaining light values are derived
    /// from paper and are provisional until light mode is mocked. The canvas is
    /// `#050505` in every appearance — the photo always sits on black.
    enum Palette {
        // Surfaces
        static let canvas = Colour.hex(0x05_05_05).color
        static let deck = dynamic(dark: .hex(0x12_12_14), light: .hex(0xF4_F2_EE))
        static let sheet = dynamic(dark: .hex(0x14_14_16), light: .hex(0xF4_F2_EE))
        /// The trough a segmented control sits in.
        static let wellSegment = dynamic(dark: .hex(0x0D_0D_0F), light: .hex(0xE4_E1_DC))
        /// The scrubber track, one step deeper than a segmented trough.
        static let wellTrack = dynamic(dark: .hex(0x0B_0B_0D), light: .hex(0xDE_DB_D6))
        /// Resting chips and disabled buttons.
        static let chip = dynamic(dark: .hex(0x17_17_1A), light: .hex(0xEA_E7_E2))

        // Pressable faces, as gradients rather than flat fills.
        static let raisedFace = gradient(dark: (.hex(0x2A_2A_2F), .hex(0x1F_1F_23)),
                                         light: (.hex(0xFF_FF_FF), .hex(0xEF_EC_E7)))
        static let raisedFacePressed = gradient(dark: (.hex(0x1F_1F_23), .hex(0x17_17_1A)),
                                                light: (.hex(0xEC_E9_E4), .hex(0xE2_DF_DA)))
        /// Small icon buttons sit one step lower than a full face.
        static let raisedIcon = gradient(dark: (.hex(0x26_26_2B), .hex(0x1C_1C_20)),
                                         light: (.hex(0xFB_F9_F5), .hex(0xEB_E8_E3)))
        static let raisedIconPressed = gradient(dark: (.hex(0x1C_1C_20), .hex(0x15_15_18)),
                                                light: (.hex(0xE8_E5_E0), .hex(0xDE_DB_D6)))

        // Meaning
        /// Detents, defaults, the loaded Stock, the primary action — and never
        /// status. There is exactly one accent, and it is film-base orange.
        static let accent = accentColour.color
        /// The accent before it becomes a `Color`, so the scrubber's translucent
        /// variants are one hue rather than four hand-copied ones.
        static let accentColour = Colour.oklch(0.74, 0.15, 55)
        static let accentPressed = Colour.oklch(0.62, 0.15, 55).color
        /// Cancel text. Destructive is system red, not the accent.
        static let destructive = Colour.oklch(0.72, 0.17, 25).color
        /// The slab behind swipe-to-delete.
        static let delete = Colour.oklch(0.55, 0.19, 25).color

        // Text. The opacities are the handoff's four steps below primary.
        static let textPrimary = ink(1)
        static let textSecondary = ink(0.7)
        static let textTertiary = ink(0.55)
        static let textQuaternary = ink(0.4)
        static let textDisabled = ink(0.3)

        /// Text drawn over the canvas keeps the dark-mode ink in every
        /// appearance, because the canvas surround is always black.
        static let inkOnCanvas = darkInk.color
        static func inkOnCanvas(_ opacity: Double) -> Color { darkInk.opacity(opacity).color }

        /// The colour that stands for a Profile's process. All five sit at the
        /// accent's lightness and chroma so none of them shouts, and C-41 is the
        /// accent itself — an unexposed C-41 mask is where the accent came from.
        static func process(_ process: FilmProcess) -> Color {
            switch process {
            case .c41: accent
            case .e6: Colour.oklch(0.74, 0.11, 235).color
            case .bwSilver: Colour.oklch(0.82, 0, 0).color
            case .bwChromogenic: Colour.oklch(0.82, 0.03, 80).color
            case .ecn2: Colour.oklch(0.74, 0.11, 165).color
            }
        }

        // The scrubber track. Everything drawn inside the well, plus the
        // indicator that rides over it.
        /// A minor tick, one per step.
        static let tickMinor = dynamic(dark: .hex(0xFF_FF_FF, alpha: 0.14), light: .hex(0x00_00_00, alpha: 0.14))
        /// A major tick, one per stop or decade.
        static let tickMajor = dynamic(dark: .hex(0xFF_FF_FF, alpha: 0.28), light: .hex(0x00_00_00, alpha: 0.28))
        /// The band from the anchor to the value.
        static let trackFill = accentColour.opacity(0.28).color
        /// The anchor line, at rest.
        static let trackAnchor = ink(0.5)
        /// The anchor once the value is sitting on it, and the glow around it.
        static let trackAnchorActive = accent
        static let trackAnchorGlow = accentColour.opacity(0.8).color
        /// The end the value has run into.
        static let trackWall = ink(0.6)
        /// The glow the indicator gains while a finger is on it.
        static let indicatorGlow = accentColour.opacity(0.5).color
        /// The indicator face. Light mode is provisional, like the rest of the
        /// derived light values: a pale indicator would vanish on paper, so it
        /// inverts to ink rather than lightening further.
        static let indicatorFace = gradient(dark: (.hex(0xFF_FF_FF), .hex(0xD8_D6_D2)),
                                            light: (.hex(0x4A_48_44), .hex(0x2A_29_26)))
        /// The indicator mid-drag, which flattens to one tone.
        static let indicatorFaceDragging = gradient(dark: (.hex(0xFF_FF_FF), .hex(0xFF_FF_FF)),
                                                    light: (.hex(0x2A_29_26), .hex(0x2A_29_26)))

        // Elevation. Only `Surfaces.swift` should reach for these.
        /// The 1 pt line along a raised face's top edge.
        static let edgeHighlight = dynamic(dark: .hex(0xFF_FF_FF, alpha: 0.12), light: .hex(0xFF_FF_FF, alpha: 0.9))
        /// The half-point outline that separates a raised face from the deck.
        static let edgeHairline = dynamic(dark: .hex(0xFF_FF_FF, alpha: 0.07), light: .hex(0x00_00_00, alpha: 0.08))
        /// The hairline inside a recessed well.
        static let wellHairline = dynamic(dark: .hex(0xFF_FF_FF, alpha: 0.055), light: .hex(0x00_00_00, alpha: 0.06))
        /// What a shadow is made of, cast or inset.
        static func shade(_ opacity: Double) -> Color {
            dynamic(dark: .hex(0x00_00_00, alpha: opacity), light: .hex(0x00_00_00, alpha: opacity * 0.22))
        }

        private static let darkInk = Colour.hex(0xF2_F0_EC)
        private static let lightInk = Colour.hex(0x14_14_14)

        private static func ink(_ opacity: Double) -> Color {
            dynamic(dark: darkInk.opacity(opacity), light: lightInk.opacity(opacity))
        }

        static func dynamic(dark: Colour, light: Colour) -> Color {
            let darkUI = dark.uiColor, lightUI = light.uiColor
            return Color(uiColor: UIColor { $0.userInterfaceStyle == .light ? lightUI : darkUI })
        }

        /// A top-to-bottom face gradient that follows the appearance.
        static func gradient(dark: (Colour, Colour), light: (Colour, Colour)) -> LinearGradient {
            LinearGradient(colors: [dynamic(dark: dark.0, light: light.0),
                                    dynamic(dark: dark.1, light: light.1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - Type

extension Tokens {
    /// A named type style. SF Mono carries every number in the app, SF Pro
    /// everything else, and the mono styles set `.monospacedDigit()` so a
    /// readout cannot jitter while a value is dragging.
    struct TypeStyle: Sendable, Equatable {
        var size: CGFloat
        var weight: Font.Weight
        var isMono: Bool
        /// Leading, where the handoff gives one. `nil` keeps the font's own.
        var lineHeight: CGFloat?
        var tracking: CGFloat = 0
        var textCase: Text.Case?

        var font: Font {
            let base = Font.system(size: size, weight: weight, design: isMono ? .monospaced : .default)
            return isMono ? base.monospacedDigit() : base
        }

        /// The height a component should reserve for one line of this style, so
        /// a value that changes cannot move the layout around it. Where the
        /// handoff sets leading tighter than the font's own line box — the
        /// readout's 34/34 — the font wins, because SwiftUI cannot draw a line
        /// shorter than its own metrics and a clipped readout is worse than a
        /// slightly taller one.
        var slotHeight: CGFloat { max(lineHeight ?? 0, uiFont.lineHeight) }

        /// Leading beyond the font's own, which is all `lineSpacing` can add.
        var lineSpacing: CGFloat { max(0, (lineHeight ?? 0) - uiFont.lineHeight) }

        private var uiFont: UIFont {
            let uiWeight = UIFont.Weight(weight)
            return isMono ? .monospacedSystemFont(ofSize: size, weight: uiWeight)
                          : .systemFont(ofSize: size, weight: uiWeight)
        }
    }
}

extension Tokens.TypeStyle {
    /// The active control's value. Fixed width, one line, unit in a separate run.
    static let readout = Self(size: 34, weight: .medium, isMono: true, lineHeight: 34, tracking: -0.5)
    /// The unit beside a readout, and any secondary numeral.
    static let unit = Self(size: 15, weight: .medium, isMono: true)
    /// The number on a parameter chip.
    static let chipValue = Self(size: 12, weight: .medium, isMono: true)
    /// `● DETENT` and its siblings.
    static let tag = Self(size: 10, weight: .medium, isMono: true, tracking: 0.8, textCase: .uppercase)
    /// A stage's name in the selector.
    static let stageName = Self(size: 13, weight: .semibold, isMono: false)
    /// The name of the parameter the active control is editing.
    static let controlName = Self(size: 13, weight: .medium, isMono: false)
    /// A chip's name, and body copy in a sheet.
    static let chipName = Self(size: 12, weight: .medium, isMono: false)
    static let sheetBody = Self(size: 15, weight: .medium, isMono: false)
    /// The caption slot under the active control.
    static let caption = Self(size: 11, weight: .regular, isMono: false, lineHeight: 14)
    /// The sub-label under the stage selector.
    static let subLabel = Self(size: 11, weight: .regular, isMono: false, lineHeight: 14)
    /// The word under an action-row button.
    static let actionLabel = Self(size: 10, weight: .medium, isMono: false)
}

extension View {
    /// Applies a named type style: face, size, weight, tracking and leading.
    func typeStyle(_ style: Tokens.TypeStyle) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
            .textCase(style.textCase)
    }
}

private extension UIFont.Weight {
    init(_ weight: Font.Weight) {
        switch weight {
        case .ultraLight: self = .ultraLight
        case .thin: self = .thin
        case .light: self = .light
        case .medium: self = .medium
        case .semibold: self = .semibold
        case .bold: self = .bold
        case .heavy: self = .heavy
        case .black: self = .black
        default: self = .regular
        }
    }
}

// MARK: - Metrics

extension Tokens {
    /// Spacing, radii and hit targets. The spacing scale has exactly seven steps
    /// and the radii are per-component rather than a scale, because the handoff
    /// gives them per component.
    enum Metrics {
        static let space4: CGFloat = 4
        static let space5: CGFloat = 5
        static let space6: CGFloat = 6
        static let space10: CGFloat = 10
        static let space14: CGFloat = 14
        static let space16: CGFloat = 16
        static let space20: CGFloat = 20

        static let chipRadius: CGFloat = 9
        static let segmentRadius: CGFloat = 8
        /// A segmented trough.
        static let troughRadius: CGFloat = 11
        /// The scrubber track. §4 of the handoff gives the track `radius 7` and
        /// §2 gives the segmented trough `radius 11`; §10's "trough/track 7 · 11"
        /// is that pair, written in the other order.
        static let trackRadius: CGFloat = 7
        static let buttonRadius: CGFloat = 12
        static let sheetRadius: CGFloat = 22
        static let filmstripCellRadius: CGFloat = 3

        /// Chips draw 34 pt tall and claim a 44 pt hit area around that.
        static let chipHeight: CGFloat = 34
        static let minimumHitTarget: CGFloat = 44
    }
}

// MARK: - Track

extension Tokens {
    /// The scrubber's own dimensions, from §4 of the handoff. They sit apart from
    /// `Metrics` because each one belongs to this one component, where a spacing
    /// step or a hit target belongs to all of them. The track's corner radius is
    /// the exception and stays in `Metrics` with the other radii.
    enum Track {
        static let height: CGFloat = 28
        /// A tick, an anchor and an end wall, in the widths the handoff gives.
        static let tickWidth: CGFloat = 1
        static let tickInsetMinor: CGFloat = 6
        static let tickInsetMajor: CGFloat = 2
        static let anchorWidth: CGFloat = 2
        static let wallWidth: CGFloat = 3

        /// The closest two minor ticks may sit before the row reads as a solid
        /// band. Temperature steps every 50 K over 8000 K, which is 160 ticks
        /// across the track and would draw as fill rather than as steps.
        static let minimumTickSpacing: CGFloat = 4
        /// Roughly how many major ticks span the track. The interval itself is
        /// rounded to 1, 2 or 5 times a power of ten, so it lands on a stop for
        /// Exposure and a decade for Temperature without either being named.
        static let majorTickTarget: Double = 6

        static let indicatorWidth: CGFloat = 4
        static let indicatorRadius: CGFloat = 2
        /// How far the indicator stands proud of the track, top and bottom.
        static let indicatorOverhang: CGFloat = 4
        /// How far inside the end the indicator parks at a range limit.
        static let indicatorEndInset: CGFloat = 2

        /// The glow around an anchor the value is sitting on, and around the
        /// indicator while a finger is on it. The handoff writes these as 8 px
        /// and 12 px, halved here like every other blur in this file.
        static let anchorGlowRadius: CGFloat = 4
        static let indicatorGlowRadius: CGFloat = 6
        /// What a disabled track fades to.
        static let disabledOpacity: Double = 0.4
    }
}

// MARK: - Elevation

extension Tokens {
    /// The geometry of the three surfaces, in points, so `Surfaces.swift` states
    /// no number of its own. SwiftUI's blur radius is about half the CSS blur the
    /// handoff writes, so every blur here is the handoff's value halved.
    enum Elevation {
        /// The shadow a raised face casts, at rest and once it has travelled.
        static let castBlur: CGFloat = 1.5
        static let castOffset: CGFloat = 1
        static let castBlurPressed: CGFloat = 1
        static let castOffsetPressed: CGFloat = 0.5
        static let castShade: Double = 0.7

        /// The 1 pt highlight along a face's top edge, and the half-point outline
        /// that separates it from the deck.
        static let highlightWidth: CGFloat = 1
        static let hairlineWidth: CGFloat = 0.5

        /// What that highlight becomes when the face goes down.
        static let pressedInsetBlur: CGFloat = 1.5
        static let pressedInsetOffset: CGFloat = 2
        static let pressedInsetShade: Double = 0.7

        /// How far light falls into a well, and how little comes back.
        static let wellInsetOffset: CGFloat = 1
        static let troughBlur: CGFloat = 1
        static let troughShade: Double = 0.8
        static let trackBlur: CGFloat = 1.5
        static let trackShade: Double = 0.9

        /// The scrubber indicator's own shadow: a dark hairline right against
        /// the edge so it separates from a light track, and a short cast below.
        static let indicatorHairlineWidth: CGFloat = 0.5
        static let indicatorCastBlur: CGFloat = 1.5
        static let indicatorCastOffset: CGFloat = 1
        static let indicatorShade: Double = 0.8
    }
}

// MARK: - Motion

extension Tokens {
    /// Durations, in seconds. Stage and parameter switching must feel instant;
    /// nothing here springs.
    ///
    /// Reduce Motion removes animation only. Every haptic still fires, and a
    /// reset becomes an instant snap rather than a slower one.
    enum Motion {
        static let parameterSwitch: Double = 0.06
        static let stageSwitch: Double = 0.08
        static let captionCrossfade: Double = 0.09
        /// The detent tick brightening, the filmstrip's accent ring, the compare
        /// pill inverting.
        static let tick: Double = 0.12
        static let reset: Double = 0.16

        /// The 4 pt slide a stage switch carries, in the direction of light.
        static let stageSlide: CGFloat = 4
        /// How far the indicator sticks to a detent before it lets go.
        static let detentStick: CGFloat = 6
        /// A pressed button's implied travel.
        static let pressDepth: CGFloat = 1

        /// An ease-out of the given duration, or nothing under Reduce Motion.
        static func ease(_ duration: Double, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeOut(duration: duration)
        }
    }
}

// MARK: - Preview

/// Every colour, type style and metric in one place, so a change to a token is
/// visible without opening a screen. Surfaces have their own catalogue in
/// `Surfaces.swift`.
private struct TokenCatalogue: View {
    private let surfaces: [(String, Color)] = [
        ("canvas", Tokens.Palette.canvas), ("deck", Tokens.Palette.deck),
        ("sheet", Tokens.Palette.sheet), ("well · segment", Tokens.Palette.wellSegment),
        ("well · track", Tokens.Palette.wellTrack), ("chip", Tokens.Palette.chip),
    ]
    private let meanings: [(String, Color)] = [
        ("accent", Tokens.Palette.accent), ("accent pressed", Tokens.Palette.accentPressed),
        ("destructive", Tokens.Palette.destructive), ("delete", Tokens.Palette.delete),
    ]
    private let inks: [(String, Color)] = [
        ("primary", Tokens.Palette.textPrimary), ("secondary", Tokens.Palette.textSecondary),
        ("tertiary", Tokens.Palette.textTertiary), ("quaternary", Tokens.Palette.textQuaternary),
        ("disabled", Tokens.Palette.textDisabled),
    ]
    private let styles: [(String, Tokens.TypeStyle, String)] = [
        ("readout", .readout, "+0.0 EV"), ("unit", .unit, "5200 K"),
        ("chip value", .chipValue, "+0.3"), ("tag", .tag, "● detent"),
        ("stage name", .stageName, "Film"), ("control name", .controlName, "Exposure"),
        ("chip name", .chipName, "Halation"), ("sheet body", .sheetBody, "Portra 400"),
        ("caption", .caption, "One third of a stop over the meter."),
        ("sub-label", .subLabel, "Kodak Portra 400 · C-41"),
        ("action label", .actionLabel, "Export"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Metrics.space20) {
                section("Surfaces") { swatches(surfaces) }
                section("Faces") { faces }
                section("Meaning") { swatches(meanings) }
                section("Ink") { swatches(inks) }
                section("Process") {
                    swatches(FilmProcess.allCases.map { ($0.rawValue, Tokens.Palette.process($0)) })
                }
                section("Type") {
                    VStack(alignment: .leading, spacing: Tokens.Metrics.space10) {
                        ForEach(styles, id: \.0) { name, style, sample in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).typeStyle(.actionLabel)
                                    .foregroundStyle(Tokens.Palette.textTertiary)
                                Text(sample).typeStyle(style)
                                    .foregroundStyle(Tokens.Palette.textPrimary)
                            }
                        }
                    }
                }
            }
            .padding(Tokens.Metrics.space20)
        }
        .background(Tokens.Palette.deck)
    }

    /// The raised gradients, which are the only tokens that are not flat fills.
    private var faces: some View {
        VStack(alignment: .leading, spacing: Tokens.Metrics.space5) {
            ForEach(Array(gradients.enumerated()), id: \.offset) { _, item in
                HStack(spacing: Tokens.Metrics.space10) {
                    RoundedRectangle(cornerRadius: Tokens.Metrics.chipRadius)
                        .fill(item.1)
                        .frame(width: 64, height: Tokens.Metrics.chipHeight)
                    Text(item.0).typeStyle(.chipName).foregroundStyle(Tokens.Palette.textPrimary)
                }
            }
        }
    }

    private var gradients: [(String, LinearGradient)] {
        [("raised face", Tokens.Palette.raisedFace),
         ("raised face · pressed", Tokens.Palette.raisedFacePressed),
         ("raised icon", Tokens.Palette.raisedIcon),
         ("raised icon · pressed", Tokens.Palette.raisedIconPressed)]
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Metrics.space10) {
            Text(title).typeStyle(.stageName).foregroundStyle(Tokens.Palette.textSecondary)
            content()
        }
    }

    private func swatches(_ items: [(String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Metrics.space5) {
            ForEach(items, id: \.0) { name, colour in
                HStack(spacing: Tokens.Metrics.space10) {
                    RoundedRectangle(cornerRadius: Tokens.Metrics.chipRadius)
                        .fill(colour)
                        .frame(width: 64, height: Tokens.Metrics.chipHeight)
                        .overlay(RoundedRectangle(cornerRadius: Tokens.Metrics.chipRadius)
                            .strokeBorder(Tokens.Palette.textQuaternary, lineWidth: 0.5))
                    Text(name).typeStyle(.chipName).foregroundStyle(Tokens.Palette.textPrimary)
                }
            }
        }
    }
}

#Preview("Tokens · dark") {
    TokenCatalogue().preferredColorScheme(.dark)
}

#Preview("Tokens · light") {
    TokenCatalogue().preferredColorScheme(.light)
}

// MARK: - Deck

extension Tokens {
    enum Deck {
        static let height: CGFloat = 316
        static let selectorHeight: CGFloat = 36
        static let segmentHeight: CGFloat = 30
        static let segmentPadding: CGFloat = 3
        static let subLabelHeight: CGFloat = 14
        static let controlHeight: CGFloat = 112
        static let headerHeight: CGFloat = 16
        static let readoutHeight: CGFloat = 34
        static let captionHeight: CGFloat = 28
        // The four slots total 106; the remaining six points separate the header.
        static let headerGap: CGFloat = 6
        static let actionHeight: CGFloat = 40
        static let actionIconWidth: CGFloat = 40
        static let actionIconHeight: CGFloat = 26
        static let chipPadding: CGFloat = 9
        static let modifiedDot: CGFloat = 5
        static let unavailableOpacity: Double = 0.35
        static let overflowStart: CGFloat = 0.92
        static let thumbnailWidth: CGFloat = 26
        static let thumbnailHeight: CGFloat = 24
        static let processEdge: CGFloat = 2
        static let stockWidth: CGFloat = 104
        static let compactChipWidth: CGFloat = 48
        static let readoutNumberWidth: CGFloat = 142
        static let border = Colour.hex(0xFFFFFF, alpha: 0.08).color
        static let captionInk = Palette.textPrimary.opacity(0.62)
        static let quietInk = Palette.textPrimary.opacity(0.5)
        static let modifiedInk = Palette.textPrimary.opacity(0.85)
    }

    enum Discrete {
        static let discDiameter: CGFloat = 30
        static let selectionRing: CGFloat = 1.5
        static let selectionHalo: CGFloat = 4
        static let cardHeight: CGFloat = 62
        static let cardRing: CGFloat = 1
        static let cardAccent = Palette.accent.opacity(0.6)
        static let glassHighlight = Colour.hex(0xFFFFFF, alpha: 0.55).color
        static let glassRim = Colour.hex(0x000000, alpha: 0.5).color
        static let glassBlur: CGFloat = 2
        static let glassOffset: CGFloat = -2
        static let pointsPerStop: CGFloat = 54
        static let hairline: CGFloat = 1.5
        static let tickerFade: CGFloat = 0.12
        static let tickerLabelY: CGFloat = 18

        static func glass(_ filter: ContrastFilter) -> Color {
            switch filter {
            case .none: .clear
            case .yellow: Colour.hex(0xD8B632).color
            case .orange: Colour.hex(0xC97929).color
            case .red: Colour.hex(0xA63B35).color
            case .green: Colour.hex(0x4D8250).color
            case .blue: Colour.hex(0x396AA3).color
            }
        }
    }
}
