import FilmEngine

/// Describes the bundled model's starting look, not verified fidelity to real film.
/// Copy is grounded in the committed stock-reference renders and model metadata;
/// see docs/pr-evidence/photographer-polish.md. Edits and output choice can alter it.
enum StockCharacter {
    static func description(for profile: Profile) -> String {
        switch profile.id {
        case "identity":
            "No film colour or texture. Start here for everyday adjustments."
        case "portra-160":
            "Muted colour, soft highlights and finer grain than Linen 400."
        case "portra-400":
            "Muted colour and soft highlights, with more grain than Linen 160."
        case "provia-100f":
            "Rich colour, deep shadows and bright, crisp highlights."
        case "velvia-50":
            "Strong contrast and saturated colour, with deep shadows."
        case "vision3-50d", "vision3-250d":
            "Daylight-balanced colour with a gentle highlight roll-off."
        case "vision3-200t", "vision3-500t":
            "Cool blues in daylight; balanced for warm indoor light."
        case "cinestill-800t":
            "Cool daylight tones and red glow around bright lights."
        case "tri-x-400":
            "Black and white with more pronounced grain than Graphite 100."
        case "t-max-100":
            "Fine-grained black and white with smooth grey tones."
        case "fomapan-100":
            "Black and white with deep shadows and bright highlights."
        default:
            profile.metadata.accuracyClaim == .synthetic
                ? "An experimental film response for exploring colour and tone."
                : "Explore this stock’s colour, contrast and texture in the photo previews."
        }
    }
}
