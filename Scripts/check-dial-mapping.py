#!/usr/bin/env python3
"""Compile the app's real dial mapping and check it without an iOS UI test target.

Run from any directory: python3 Scripts/check-dial-mapping.py
SwiftUI's Parameter type and the production TrackMap are compiled unchanged.
Only view/haptic dependencies are omitted; numeric tokens come from Tokens.swift.
"""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    subprocess.run(["swift", "build"], cwd=ROOT, check=True)
    build = Path(subprocess.check_output(
        ["swift", "build", "--show-bin-path"], cwd=ROOT, text=True).strip())
    source = (ROOT / "FilmApp/Editor/Parameter.swift").read_text()
    # Top-level closing brace of Parameter, excluding model and preview extensions.
    end = source.index("\n}", source.index("struct Parameter: Identifiable")) + 2
    parameter = source[:end]
    source = (ROOT / "FilmApp/Editor/ParameterDial.swift").read_text()
    mapping = source[source.index("extension ParameterDial {"):source.index("// MARK: - Drawing")]
    tokens = (ROOT / "FilmApp/Design/Tokens.swift").read_text()
    def token(name):
        return re.search(r"static let " + name + r": (?:CGFloat|Double) = ([0-9.]+)", tokens)[1]
    dependencies = "enum ParameterDial {}\nenum Tokens { enum Track {\n"
    for name in ["dialPointsPerStep", "indicatorEndInset", "indicatorWidth"]:
        dependencies += f"static let {name}: CGFloat = {token(name)}\n"
    dependencies += f"static let majorTickTarget: Double = {token('majorTickTarget')} }}\n"
    dependencies += f"enum Discrete {{ static let pointsPerStop: CGFloat = {token('pointsPerStop')} }}\n"
    dependencies += f"enum Motion {{ static let detentStick: CGFloat = {token('detentStick')} }} }}\n"
    with tempfile.TemporaryDirectory(prefix="dye-dial-checks-") as directory:
        folder = Path(directory)
        swift = folder / "DialChecks.swift"
        swift.write_text(parameter + "\n" + dependencies + mapping + CHECKS)
        binary = folder / "dial-checks"
        subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
                        "-I", str(build / "Modules"), str(swift),
                        *map(str, (build / "FilmEngine.build").glob("*.o")),
                        "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)


CHECKS = r"""
@main struct DialChecks {
static func main() {
    let cases: [(Parameter.Identity, ClosedRange<Double>, Double, Double?)] = [
        (.exposure, EditorRange.exposure, 1 / 6, 0),
        (.temperature, EditorRange.temperature, 50, 5500),
        (.temperature, EditorRange.temperature, 50, 3225),
        (.tint, RenderSettings.tintRange, 1, 0),
        (.exposureTime, EditorRange.exposureTimeStops, 1 / 3, 0),
        (.development, RenderSettings.developmentRange, 0.1, 0),
        (.bloom, RenderSettings.bloomRange, 0.05, 1),
        (.halation, RenderSettings.halationRange, 0.05, 1),
        (.grain, RenderSettings.grainRange, 0.05, 1),
        (.vignette, RenderSettings.vignetteRange, 0.05, 0),
        (.gateWeave, RenderSettings.gateWeaveRange, 0.05, 0),
        (.frameBorder, RenderSettings.frameBorderRange, 0.05, 0)
    ]
    for (id, range, step, detent) in cases {
        let p = Parameter(id: id, name: id.rawValue, stage: .light, value: .constant(detent ?? 0),
                          range: range, step: step, detent: detent,
                          control: id == .exposureTime ? .shutterDial : .dial, format: { String($0) })
        let map = ParameterDial.TrackMap.dial(for: p)
        var previous = range.lowerBound
        for i in 0...1000 {
            let value = map.resolve(map.lead + map.travel * CGFloat(i) / 1000).value
            precondition(range.contains(value) && value >= previous - 1e-8)
            previous = value
        }
        precondition(map.resolve(-100000).value == range.lowerBound)
        precondition(map.resolve(map.width + 100000).value == range.upperBound)
        if let detent {
            let origin = map.origin(of: detent)
            precondition(map.resolve(origin).value == detent)
            precondition(map.resolve(origin + 5).value == detent)
            precondition(map.resolve(origin - 5).value == detent)
            precondition(map.resolve(origin + 30).value >= detent)
            precondition(map.resolve(origin - 30).value <= detent)
        }
        print("PASS", id.rawValue)
    }
    print("All dial mapping checks passed")
}}
"""

if __name__ == "__main__":
    main()
