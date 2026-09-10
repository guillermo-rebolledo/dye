#if os(macOS)
import Foundation
import FilmEngine

@main
struct ProfileBaker {
    static func main() async {
        do { try await run(Array(CommandLine.arguments.dropFirst())) }
        catch {
            FileHandle.standardError.write(Data("ProfileBaker: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        let usage = "Usage: ProfileBaker bake <curve-directory> <output.filmprofile> | validate <curve-directory> <profile.filmprofile> <report-prefix> [tolerance] | validate-model <curve-directory> <profile.filmprofile> <report.json>"
        if arguments == ["--help"] { print(usage); return }
        guard let command = arguments.first else { throw FilmError.invalid(usage) }
        switch command {
        case "bake":
            guard arguments.count == 3 else { throw FilmError.invalid(usage) }
            let curves = try CurveSet(directory: URL(fileURLWithPath: arguments[1]))
            let profile = try bake(curves)
            let output = URL(fileURLWithPath: arguments[2])
            guard output.pathExtension == "filmprofile" else { throw FilmError.invalid("Output must use .filmprofile extension") }
            try ProfileContainer.encode(profile).write(to: output, options: .atomic)
            print("Baked \(profile.id) → \(output.path)")
        case "validate":
            guard (4...5).contains(arguments.count) else { throw FilmError.invalid(usage) }
            let tolerance = arguments.count == 5 ? Double(arguments[4]) : 0.03
            guard let tolerance, tolerance.isFinite, tolerance >= 0 else { throw FilmError.invalid("Tolerance must be a finite nonnegative error") }
            let curves = try CurveSet(directory: URL(fileURLWithPath: arguments[1]))
            let profile = try ProfileContainer.load(from: URL(fileURLWithPath: arguments[2]))
            let rows = try await stepWedge(curves: curves, profile: profile)
            try writeStepWedge(rows, prefix: URL(fileURLWithPath: arguments[3]))
            guard let maximumError = rows.map(\.error).max(), maximumError.isFinite,
                  rows.allSatisfy({ $0.error.isFinite && $0.error <= $0.stage.tolerance(default: tolerance) }) else {
                throw FilmError.invalid("Step Wedge exceeds tolerance \(tolerance); inspect the CSV/SVG report")
            }
            print("Step Wedge passed: \(rows.count) samples, max absolute error \(maximumError), tolerance \(tolerance)")
        case "validate-model":
            guard arguments.count == 4 else { throw FilmError.invalid(usage) }
            let curves = try CurveSet(directory: URL(fileURLWithPath: arguments[1]))
            let profile = try ProfileContainer.load(from: URL(fileURLWithPath: arguments[2]))
            let results = try validateNumericalModel(curves: curves, profile: profile)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(results).write(to: URL(fileURLWithPath: arguments[3]), options: .atomic)
            guard results.allSatisfy({ $0.maximumError <= 0.03 }) else {
                throw FilmError.invalid("Composed density/output model exceeds 0.03; inspect the numerical report")
            }
            print("Numerical model passed; independent photographic validation is separate")
        default: throw FilmError.invalid(usage)
        }
    }
}
#else
#error("ProfileBaker is a macOS-only offline tool and must not be linked into FilmApp")
#endif
