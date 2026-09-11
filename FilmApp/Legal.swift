import Foundation

/// The text the app is obliged to be able to show: what the Catalogue's names are and
/// are not, who is not affiliated with whom, and what the Curve Sets were built from.
/// It lives in one place because the same words go into the store description and the
/// support page, and three copies of a legal paragraph drift.
enum Legal {
    /// Where a support page and a privacy policy live. Both are mandatory App Store
    /// Connect fields, so the app links the same URLs the listing declares.
    ///
    /// **Neither page is published yet, so both links are dead.** They are here as
    /// the single place to change when they are, and publishing them is a submission
    /// blocker in `docs/release.md` — shipping a dead Privacy Policy row is worse
    /// than shipping none.
    static let supportURL = URL(string: "https://memoji.app/dye/support")!
    static let privacyPolicyURL = URL(string: "https://memoji.app/dye/privacy")!

    /// What the qualifier in front of a Display Name means. Shown in the Film Stock
    /// browser, where every name in the Catalogue is on screen at once.
    static let qualifierExplanation = """
        Every stock that models a real film is marked Modelled: it is built from \
        published data, and has never been compared with a photograph of the film. \
        Approx. means more than Modelled, not less — the manufacturer publishes no \
        usable measurement of at least one parameter, so a value borrowed from a \
        related stock stands in for it. The synthetic studies and No Film Stock model \
        no film at all, so they are not marked.
        """

    /// What the five synthetic studies at the end of the Catalogue are. Shown in the
    /// Film Stock browser at the point where they begin, because a name ending in
    /// "study" is not enough to tell a photographer that the entries after it model
    /// no film that was ever sold.
    static let studiesExplanation = """
        Calibration patterns, not films. They model no stock, and exist so the \
        pipeline can be checked against a known answer.
        """

    /// The non-affiliation statement. The Catalogue ships under names of its own, so
    /// no manufacturer's mark appears in the app — but the store description names
    /// the films that inspired the looks, and this is the paragraph that qualifies it.
    static let disclaimer = """
        Dye is an independent app. It is not affiliated with, endorsed by, or \
        sponsored by Eastman Kodak Company, Kodak Alaris, FUJIFILM Corporation, \
        CineStill Film, FOMA BOHEMIA, or any other film manufacturer. All product \
        names and trademarks are the property of their respective owners.

        The film stocks in Dye carry names of Dye's own. They are physical models \
        built from published measurements, not reproductions of any manufacturer's \
        product, and no photographic comparison against real film has been made.
        """

    /// Third-party attribution. The CIE datasets are CC BY-SA 4.0, which is a live
    /// obligation rather than a courtesy; `NOTICE.md` carries the same text.
    static let acknowledgements = """
        Colour matching functions and illuminant data

        CIE 1931 2° standard colorimetric observer (DOI 10.25039/CIE.DS.xvudnb9b) \
        and CIE standard illuminant D65 (DOI 10.25039/CIE.DS.hjfjmt59), \
        © Commission Internationale de l'Éclairage. Used under CC BY-SA 4.0.

        Changes: resampled to the working wavelength grid and stored as CSV. The \
        derived files and their derivatives are themselves licensed CC BY-SA 4.0. \
        Licence text: https://creativecommons.org/licenses/by-sa/4.0/

        Film characteristic curves

        Dye's stock models are built from independent numerical readings taken from \
        published manufacturer datasheets and technical publications. Dye contains \
        no datasheet PDFs and no reproduced chart artwork, and claims no open-content \
        licence over any manufacturer's material.

        Photographs

        Dye contains no bundled photographs. Every image it draws is generated at \
        run time from the model.
        """
}
