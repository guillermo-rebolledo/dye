import Foundation

/// The text the app is obliged to be able to show: what the Catalogue's names are and
/// are not, who is not affiliated with whom, and what the Curve Sets were built from.
/// It lives in one place because the same words go into the store description and the
/// support page, and three copies of a legal paragraph drift.
enum Legal {
    /// Where the privacy policy and the support page are published. Both are mandatory
    /// App Store Connect fields and Apple needs a reachable page at each, which is the
    /// only reason these exist: the app itself shows the same words from
    /// `privacyPolicy` and `support` below, on device, without a network.
    ///
    /// `Scripts/build-site.py` renders both pages from those two properties and
    /// `Scripts/test_ci_site.py` fails the build if the published pages and the app
    /// ever disagree. Change the words here, never in the HTML.
    static let supportURL = URL(string: "https://guillermo-rebolledo.github.io/dye/support/")!
    static let privacyPolicyURL = URL(string: "https://guillermo-rebolledo.github.io/dye/privacy/")!

    /// Where a problem with Dye goes. A public tracker rather than a mailbox: it is
    /// already where the code lives, and it does not publish anybody's address.
    static let issueTrackerURL = URL(string: "https://github.com/guillermo-rebolledo/dye/issues")!

    /// The privacy policy, shown on device and published at `privacyPolicyURL`.
    ///
    /// Every sentence here is a claim about what the code does, and the code is the
    /// authority: no networking, no analytics, no third-party SDK, an add-only Photos
    /// authorisation, and Presets in a local store. If any of those stops being true,
    /// this paragraph is wrong before the App Privacy answers are.
    static let privacyPolicy = """
        Dye collects nothing.

        Dye has no analytics, no advertising, no crash reporting and no third-party \
        software development kits. It makes no network connection of its own, so \
        there is nowhere for anything to go, and there is no account to create.

        Your photographs

        You choose a photograph with the system picker. iOS hands Dye a copy of the \
        one you chose and nothing else, so Dye never has access to your photo library.

        Everything Dye then does to that photograph happens on your device. When you \
        save an export, Dye asks permission to add to your photo library. That \
        permission is add-only: it can put a new picture in, and it cannot read what \
        is already there. Refusing it does not stop the export, which you can still \
        share from inside the app.

        An export has to become a file before it can be saved or shared. Dye keeps at \
        most one, replaces it the next time you export, and deletes it when the app \
        next starts.

        What stays on your device

        Presets you save are stored on your device only, and go wherever your own \
        iPhone backups go. There is no account, and no copy anywhere else.

        Leaving the app

        Opening a link from Settings hands off to your browser. What happens after \
        that is between you and the site you land on.

        Children

        Dye is not directed at children, and collects nothing from anyone.

        Changes

        If this policy changes, the new version appears here and in the app. A change \
        would mean Dye had started doing something it does not do today.

        Last updated 11 September 2026.
        """

    /// The support page, shown on device and published at `supportURL`.
    static let support = """
        Dye renders your photograph through a physical model of a film stock. It runs \
        on your device, with no account and no network.

        Requirements

        An iPhone running iOS 17 or later.

        Reporting a problem

        Problems and questions go to Dye's public issue tracker on GitHub.

        Please say which iPhone you are using, which version of iOS it runs, and the \
        version of Dye printed at the bottom of Settings. If one particular \
        photograph fails, say what kind of file it is and where it came from.

        What Dye does not claim

        Dye's film stocks carry names of Dye's own. They are physical models built \
        from published measurements, and none of them has been compared against a \
        photograph taken on the film it models — which is what the word Modelled \
        beneath a stock's name is there to say. Approx. marks a stock where a \
        published measurement was missing altogether and a value from a related stock \
        stands in for it.

        Dye is an iPhone app. There is no iPad layout and no Mac version.
        """

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
