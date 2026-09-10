#!/usr/bin/env python3
"""Assert the bundle facts an App Store upload rejects, against a real archive.

None of these can be checked by a unit test: they are properties of the thing
`xcodebuild archive` produces, and every one of them has failed an upload for
somebody. Running this in CI means a regression fails the build rather than the
upload, which is the difference between a five-minute fix and a lost afternoon.

    python3 Scripts/check-archive.py /tmp/Dye.xcarchive

Exits non-zero, and says which expectation failed, on any mismatch.
"""

import plistlib
import re
import subprocess
import sys
import pathlib

# What `docs/release.md` says the bundle must be. Change these together with the
# build settings, never one without the other.
BUNDLE_IDENTIFIER = "app.memoji.dye"
DISPLAY_NAME = "Dye"
# 1 is iPhone. iPad is deliberately not declared: there is no iPad layout, no iPad
# verification and no iPad screenshot set. See REL-05.
DEVICE_FAMILY = [1]
CATEGORY = "public.app-category.photography"


def is_identifier(line):
    """A Profile id or a path built from one, which is never shown to a user."""
    return bool(re.fullmatch(r"[/\w.\-]*", line.strip()))


def fail(message):
    print(f"check-archive: {message}", file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) != 2:
        fail("usage: check-archive.py <path to .xcarchive>")
    archive = pathlib.Path(sys.argv[1])
    applications = archive / "Products/Applications"
    apps = sorted(applications.glob("*.app")) if applications.is_dir() else []
    if len(apps) != 1:
        fail(f"expected exactly one .app in {applications}, found {len(apps)}")
    app = apps[0]

    info = plistlib.loads((app / "Info.plist").read_bytes())
    problems = []

    def expect(key, predicate, description):
        value = info.get(key)
        if not predicate(value):
            problems.append(f"{key} is {value!r}; expected {description}")

    # REL-01. Emitted by compiling an asset catalogue containing an AppIcon set.
    # Its absence fails upload validation outright.
    icons = info.get("CFBundleIcons") or {}
    icon_name = info.get("CFBundleIconName") or icons.get("CFBundlePrimaryIcon", {}).get("CFBundleIconName")
    if not icon_name:
        problems.append("no CFBundleIconName anywhere in Info.plist; the asset catalogue did not compile an AppIcon")
    # REL-02. Empty when MARKETING_VERSION / CURRENT_PROJECT_VERSION are unset.
    expect("CFBundleShortVersionString", lambda v: bool(v) and re.fullmatch(r"\d+(\.\d+){0,2}", v),
           "a period-separated numeric version")
    expect("CFBundleVersion", lambda v: bool(v) and v.isdigit(), "a positive integer build number")
    # REL-03. Without it the Home screen reads FilmApp and the permission alert
    # is titled FilmApp while its body says Dye.
    expect("CFBundleDisplayName", lambda v: v == DISPLAY_NAME, DISPLAY_NAME)
    expect("CFBundleIdentifier", lambda v: v == BUNDLE_IDENTIFIER, BUNDLE_IDENTIFIER)
    # REL-05. The declaration must match the decision, not the Xcode default.
    expect("UIDeviceFamily", lambda v: v == DEVICE_FAMILY, DEVICE_FAMILY)
    # REL-40. Every upload stalls on the encryption question until it is answered.
    expect("ITSAppUsesNonExemptEncryption", lambda v: v is False, "False")
    expect("LSApplicationCategoryType", lambda v: v == CATEGORY, CATEGORY)
    # REL-04. The permission the app actually uses, and only that one: declaring
    # NSPhotoLibraryUsageDescription would prompt for access it never takes.
    expect("NSPhotoLibraryAddUsageDescription", lambda v: bool(v), "a non-empty purpose string")
    if "NSPhotoLibraryUsageDescription" in info:
        problems.append("NSPhotoLibraryUsageDescription is declared; Dye never reads the library")

    # REL-04. An empty UILaunchScreen takes the system default, which is white, and
    # the app then forces dark onto a #050505 canvas.
    if (info.get("UILaunchScreen") or {}).get("UIColorName") != "LaunchBackground":
        problems.append(f"UILaunchScreen is {info.get('UILaunchScreen')!r}; expected UIColorName LaunchBackground")

    # REL-07. Present at the root of the .app, not merely in the repository.
    if not (app / "PrivacyInfo.xcprivacy").is_file():
        problems.append("PrivacyInfo.xcprivacy is missing from the app bundle")

    # REL-06. The resource bundle SPM produces has never been verified inside a
    # signed archive, and two launch-path lookups read out of it.
    bundles = list(app.glob("*.bundle"))
    engine = next((b for b in bundles if "FilmEngine" in b.name), None)
    if engine is None:
        problems.append(f"no FilmEngine resource bundle in the app; found {[b.name for b in bundles]}")
    else:
        for required in ["Metal/Pipeline.metal"]:
            if not (engine / required).is_file():
                problems.append(f"{engine.name} is missing {required}")
        catalogue = sorted((engine / "Catalogue").glob("*.filmprofile"))
        if len(catalogue) != 17:
            problems.append(f"expected 17 Profiles in the Catalogue, found {len(catalogue)}")

    # REL-12 / REL-13. No manufacturer mark may be *shown* to a user. That is a claim
    # about names, so it is checked where names live: the app binary's own literals
    # and every Display Name in the Catalogue.
    #
    # Profile *ids* — `portra-400`, `vision3-500t` — deliberately still carry the
    # marks and are excluded here. They are internal handles: they key saved Presets,
    # Golden Image fixtures and the CI Step Wedge patterns, they are never shown, and
    # since the Export filename moved to the Display Name there is no path from an id
    # to anything a user reads. Renaming them is a separate, larger change.
    marks = ["Kodak", "Portra", "Tri-X", "T-Max", "Vision3", "Fujifilm", "Provia",
             "Velvia", "CineStill", "Cinestill", "Fomapan", "Wratten", "Kodachrome", "Ilford"]
    pattern = r"\|".join(marks)
    binary = subprocess.run(["strings", str(app / info["CFBundleExecutable"])],
                            capture_output=True, text=True).stdout.splitlines()
    for line in binary:
        # The non-affiliation disclaimer has to name the rights holders to disclaim
        # any affiliation with them; that is the one place a mark belongs.
        if re.search(pattern, line) and "not affiliated" not in line and not is_identifier(line):
            problems.append(f"the app binary contains a manufacturer mark: {line.strip()[:80]!r}")
    for profile in sorted((engine / "Catalogue").glob("*.filmprofile")) if engine else []:
        head = profile.read_bytes()[:4096].decode("utf-8", "replace")
        name = re.search(r'"displayName":"([^"]*)"', head)
        if name and re.search(pattern, name.group(1)):
            problems.append(f"{profile.name} ships under a manufacturer mark: {name.group(1)!r}")

    # REL-35. Crashes from TestFlight and the App Store are only symbolicated if
    # the archive carries its dSYMs.
    if not list((archive / "dSYMs").glob("*.dSYM")):
        problems.append("the archive carries no dSYMs; crashes will not symbolicate")

    if problems:
        for problem in problems:
            print(f"check-archive: {problem}", file=sys.stderr)
        sys.exit(1)
    print(f"check-archive: {app.name} looks uploadable "
          f"({info['CFBundleDisplayName']} {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}))")


if __name__ == "__main__":
    main()
