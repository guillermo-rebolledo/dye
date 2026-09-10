import Foundation
import FilmEngine

/// What the app shows a user when something fails, and what it keeps back.
///
/// `FilmError`'s messages are the engine's own vocabulary — they name Profile ids,
/// payload names, shader names, the Working Space and the Density Curve — and they
/// are the right vocabulary for a stack trace and for the tests that depend on them.
/// They are the wrong vocabulary for a person holding a phone. So the engine keeps
/// its words and this decides which of them a user ever reads: a `PhotoProblem` is
/// already written for the user and passes through, and everything else becomes one
/// sentence about what did not happen, with the engine's own text behind `details`.
struct UserFacingError: Equatable {
    /// The sentence on screen.
    let message: String
    /// The engine's own words, for a bug report. Never shown unless asked for.
    let details: String?
    /// Set when the failure is a photograph the app could still open on the user's
    /// say-so, rather than one it cannot open at all.
    let photoProblem: PhotoProblem?

    /// The failure as it happened, classified by what the user was trying to do.
    /// `doing` completes the sentence "…could not be": "opened", "exported", "saved".
    init(_ error: Error, doing activity: Activity) {
        if case let FilmError.photo(problem) = error {
            message = problem.message
            details = nil
            photoProblem = problem
            return
        }
        message = activity.failureSentence
        // A cancellation is not a failure and never reaches here; anything else is
        // either an engine fault or a system one, and both read the same to a user.
        details = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        photoProblem = nil
    }

    /// Only the app knows what the user was doing when the engine gave up, and that
    /// is the whole difference between a useful sentence and "Cannot encode filmResponse".
    enum Activity {
        case openingPhoto, loadingCatalogue, loadingStock, rendering, exporting, savingToPhotos, exportingLUT, savingPreset

        var failureSentence: String {
            switch self {
            case .openingPhoto: "This photo could not be opened."
            case .loadingCatalogue: "The film stocks could not be loaded. Reinstalling Dye should fix it."
            case .loadingStock: "This film stock could not be loaded. Choose another one."
            case .rendering: "This photo could not be rendered."
            case .exporting: "The export could not be completed."
            case .savingToPhotos: "The photo could not be added to your library."
            case .exportingLUT: "The LUT could not be created."
            case .savingPreset: "This preset could not be saved."
            }
        }
    }
}
