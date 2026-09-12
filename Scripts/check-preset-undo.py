#!/usr/bin/env python3
"""Exercise the real EditorModel on macOS, without introducing an iOS test host.

Only UI previews and the picker view are omitted. Model, bindings, photo loading,
validation and snapshot code are compiled unchanged against the real FilmEngine.
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
    parameter = (ROOT / "FilmApp/Editor/Parameter.swift").read_text().split("// MARK: - Preview")[0]
    # `PickedPhoto` only, never the picker view: the split is on the file's own
    # section marker rather than on a sentence, so rewording a doc comment cannot
    # quietly feed the whole file in and leave these checks compiling something else.
    picker = (ROOT / "FilmApp/Editor/SinglePhotoPicker.swift").read_text().split(
        "// MARK: - Picker")[0]
    tokens = (ROOT / "FilmApp/Design/Tokens.swift").read_text()
    def token(name):
        return re.search(r"static let " + name + r": (?:CGFloat|Double) = ([0-9.]+)", tokens)[1]
    dependencies = "enum Tokens { enum Track {\n"
    for name in ["dialPointsPerStep", "adjustmentPointsPerStep"]:
        dependencies += f"static let {name}: CGFloat = {token(name)}\n"
    dependencies += "}\nenum Discrete { static let pointsPerStop: CGFloat = " + token("pointsPerStop") + " } }\n"
    with tempfile.TemporaryDirectory(prefix="dye-preset-checks-") as directory:
        folder = Path(directory)
        (folder / "Parameter.swift").write_text(parameter)
        (folder / "PickedPhoto.swift").write_text(picker)
        (folder / "Checks.swift").write_text("import SwiftUI\nimport FilmEngine\nimport ImageIO\nimport UniformTypeIdentifiers\n" + dependencies + CHECKS)
        sources = [ROOT / name for name in ["FilmApp/EditorModel.swift", "FilmApp/UserFacingError.swift",
                   "FilmApp/Editor/EditorLookSnapshot.swift"]]
        binary = folder / "preset-checks"
        subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
                        "-I", str(build / "Modules"), *map(str, sources),
                        *map(str, sorted(folder.glob("*.swift"))),
                        *map(str, (build / "FilmEngine.build").glob("*.o")),
                        "-o", str(binary)], check=True)
        subprocess.run([str(binary)], cwd=ROOT, check=True)


CHECKS = r'''
@main struct PresetChecks {
    @MainActor static func main() async throws {
        let model = EditorModel()
        model.catalogue = try ProfileCatalogue.bundled().profiles
        model.selectedStock = "tri-x-400"
        model.settings.exposureStops = 0.7
        model.settings.contrastFilter = .red
        model.settings.adjustments.shadows = 0.4
        model.toggleBypass(.shadows)
        let previous = model.settings
        try model.applyPreset(stockID: "portra-400", settings: RenderSettings())
        precondition(model.canUndoPresetApplication && !model.isBypassed(.shadows))
        precondition(model.settings.contrastFilter == .none)
        model.undoPresetApplication()
        precondition(model.selectedStock == "tri-x-400" && model.settings == previous)
        precondition(model.isBypassed(.shadows) && !model.canUndoPresetApplication)
        model.toggleBypass(.shadows)
        precondition(model.settings.adjustments.shadows == 0.4)
        print("PASS restores stock, incompatible filter, settings and bypassed values")

        try model.applyPreset(stockID: "identity", settings: RenderSettings())
        do {
            try model.applyPreset(stockID: "missing", settings: RenderSettings())
            preconditionFailure("Missing stock accepted")
        } catch { }
        var invalid = RenderSettings()
        invalid.exposureStops = .nan
        do {
            try model.applyPreset(stockID: "identity", settings: invalid)
            preconditionFailure("Invalid settings accepted")
        } catch { }
        precondition(model.canUndoPresetApplication && model.selectedStock == "identity")
        model.undoPresetApplication()
        precondition(model.selectedStock == "tri-x-400" && model.settings.adjustments.shadows == 0.4)
        print("PASS failed applications preserve the current look and existing undo")

        try model.applyPreset(stockID: "identity", settings: RenderSettings())
        var second = RenderSettings()
        second.exposureStops = 1
        try model.applyPreset(stockID: "identity", settings: second)
        model.undoPresetApplication()
        precondition(model.settings == RenderSettings() && !model.canUndoPresetApplication)
        let restored = model.settings
        model.undoPresetApplication()
        precondition(model.settings == restored)
        print("PASS repeated applications undo only the most recent preset; second undo is harmless")

        try model.applyPreset(stockID: "identity", settings: RenderSettings())
        let sameSettings = model.settings
        model.settings = sameSettings
        precondition(model.canUndoPresetApplication)
        model.settings.exposureStops = 0.5
        precondition(!model.canUndoPresetApplication)
        try model.applyPreset(stockID: "identity", settings: RenderSettings())
        model.selectedStock = "portra-400"
        precondition(!model.canUndoPresetApplication)
        try model.applyPreset(stockID: "identity", settings: second)
        model.stashedAdjustments[.shadows] = 0.4
        precondition(!model.canUndoPresetApplication)
        let shadows = model.parameters(for: .adjust).first { $0.id == .shadows }!
        shadows.value.wrappedValue = shadows.defaultValue
        precondition(!model.isBypassed(.shadows) && model.settings.adjustments.shadows == 0)
        print("PASS edits invalidate undo; reset clears a bypassed adjustment")

        // Exercise the actual import path: failure retains undo, success clears it.
        try model.applyPreset(stockID: "identity", settings: RenderSettings())
        await model.open(PickedPhoto { nil })
        precondition(model.canUndoPresetApplication && model.error != nil)
        let bytes = photo()
        await model.open(PickedPhoto { bytes })
        precondition(model.beforePixels != nil && model.error == nil)
        precondition(!model.canUndoPresetApplication)
        print("PASS import failure keeps undo; opening a new photo clears it")

        // A new photograph is not the last one's picture: it opens at the initial look.
        model.selectedStock = "tri-x-400"
        model.settings.exposureStops = 0.7
        model.settings.adjustments.shadows = 0.4
        model.toggleBypass(.shadows)
        await model.open(PickedPhoto { bytes })
        precondition(model.error == nil && model.selectedStock == "identity")
        precondition(model.settings == RenderSettings() && model.stashedAdjustments.isEmpty)
        print("PASS opening a photo resets stock, settings and bypassed values")
        print("All preset undo checks passed")
    }

    static func photo() -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
                                bytesPerRow: 128, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
'''

if __name__ == "__main__":
    main()
