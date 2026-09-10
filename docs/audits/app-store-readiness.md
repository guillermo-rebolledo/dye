# App Store readiness audit

**Date:** 2026-09-10
**Commit audited:** `c19bc12` (`main`, tree clean, no untracked or ignored files)
**Scope:** everything that stands between this repository and an approved App Store
submission — bundle and build artifacts, privacy, trademark and other legal exposure,
the honesty of the app's accuracy claims, App Review Guideline compliance,
accessibility, localisation, robustness on the paths a reviewer reaches in five
minutes, release engineering, and the store listing assets that are not code.

## Method and limits

This is a **static repository audit**. It was performed on a Linux machine with **no
Swift toolchain, no Xcode, no iOS device or simulator, and no network access**.
Nothing here was built, archived, signed, run, profiled or validated. No App Store
Connect record was inspected, and Apple's live App Review Guidelines and developer
documentation could not be consulted.

Consequences you must hold in mind while reading:

- Every claim about **repository state** — a file's absence, a build setting's value,
  a line of code — was verified directly and is cited as `path:LINE` or as
  "absent from the repo".
- Every claim about **Apple's rules** is recalled from knowledge with a cutoff in
  2026 and is marked *(recalled)*. Guideline numbers, required screenshot
  dimensions, privacy-manifest obligations and the exact behaviour of
  `GENERATE_INFOPLIST_FILE` defaults **must be re-verified against the current App
  Review Guidelines and Xcode build-setting reference at submission time**.
- Anything that lives outside the repository — the paid developer account, signing
  certificates, provisioning profiles, the App Store Connect app record, agreements
  and banking, the privacy questionnaire answers — is reported as
  **unverifiable from here** and appears in *Open questions for the owner* rather
  than being asserted broken.
- Vocabulary follows [`CONTEXT.md`](../../CONTEXT.md): **Stock**, **Profile**,
  **Catalogue**, **Display Name**, **Preset**, **Approximation**, **Provenance**,
  **Export**, **Exported LUT**, **Film Stock** / **No Film Stock**.

**Companion audits.** `docs/audits/security.md` and `docs/audits/performance.md` are
**not part of commit `c19bc12`** — at the time this audit's evidence was gathered
they did not exist, and `docs/audits/` contained only `film-stock-accuracy.md`,
`film-stock-accuracy-research.md`, `film-stock-accuracy-probe.py`,
`photo-open-responsiveness.md` and `film-stock-accuracy-review/`. Both have since
appeared as untracked files in the working tree, written in parallel with this one.
Where this audit needed data-flow, memory or robustness detail it derived it
independently, and it says so at each point. Cross-references to `SEC-*` and `PERF-*`
findings are given where the three audits reach the same conclusion by different
routes; **they were not used as a source here**, so if any of them disagrees with a
finding below, re-check the code rather than assuming one of the three is right.

---

## Blocking summary

These are the items that make submission **literally impossible** or that will
produce a rejection or an upload failure. Work them first, top to bottom.

| # | ID | What stops you |
| --- | --- | --- |
| 1 | REL-01 | **No app icon and no asset catalogue exist anywhere in the repo.** `xcodebuild archive` / App Store Connect upload validation fails on a missing `CFBundleIconName` *(recalled)*. |
| 2 | REL-02 | **No `MARKETING_VERSION` and no `CURRENT_PROJECT_VERSION`.** With `GENERATE_INFOPLIST_FILE = YES` the generated `CFBundleShortVersionString` / `CFBundleVersion` resolve to empty. Upload is rejected *(recalled)*. |
| 3 | REL-03 | **The app is called `FilmApp` on the Home screen**, not Dye. No `CFBundleDisplayName`, and `PRODUCT_NAME = $(TARGET_NAME)`. |
| 4 | REL-06 | **The app has never been built for Release, never archived, never signed.** CI builds Debug for the simulator with `CODE_SIGNING_ALLOWED=NO` only. Two force-unwrapped `Bundle.module` resource lookups sit on the launch path. |
| 5 | REL-09 | **No privacy policy URL exists anywhere.** It is a mandatory App Store Connect field for every app *(recalled)*. |
| 6 | REL-12 | **Twelve Stocks ship under live commercial trademarks** (Kodak Portra/Tri-X/T-Max/Vision3, Fujifilm Provia/Velvia, CineStill, Fomapan). Guideline 5.2 IP exposure, plus real takedown risk. This is an owner decision that gates the store listing, the screenshots and the Catalogue itself. |
| 7 | REL-38 | **No store screenshots exist at any required size.** The only captures in the repo are 1206 × 2622 (6.3") PR evidence, are stale relative to `HEAD`, and contain Apple's own simulator sample photograph. |
| 8 | REL-39 | **No support URL exists.** Mandatory App Store Connect field *(recalled)*. |
| 9 | REL-05 | **iPad is declared supported** (`TARGETED_DEVICE_FAMILY = "1,2"`) with no iPad layout work, no iPad verification and no iPad screenshots. Either drop it or fund it. |
| 10 | REL-40 | **Export-compliance / encryption is undeclared** (`ITSAppUsesNonExemptEncryption` absent), age rating, category and the privacy questionnaire are all unanswered. Every upload will stall on them. |

Two more are not strictly *blocking* but are the ones most likely to produce a
rejection under Guideline 2.3 (accurate metadata) or 2.1 (app completeness) once a
reviewer or a user looks closely:

- **REL-19** — five of the twelve named Stocks carry no **Approximation** at all and
  are therefore presented as bare, unqualified `Kodak Portra 400` while thirty of
  their forty **Provenance** entries are `artistic`, and while the project's own
  accuracy audit states that "photographic accuracy is not yet established".
- **REL-20** — a confirmed grain calibration defect that silently zeroes **Grain**
  for all nine measured colour Profiles.

---

## Full summary table

Owner types: **Eng** = Engineering, **Des** = Design, **Legal**, **Owner** =
owner-decision, **ASC** = App Store Connect / non-code.
Effort: **S** ≈ under half a day, **M** ≈ one to three days, **L** ≈ more than three days.

| ID | Title | Category | Blocking? | Owner | Effort |
| --- | --- | --- | --- | --- | --- |
| REL-01 | No app icon and no asset catalogue | Bundle | **Blocker** | Des / Eng | M |
| REL-02 | No version or build number | Bundle | **Blocker** | Eng | S |
| REL-03 | Home-screen name is `FilmApp`, not Dye | Bundle | **Blocker** | Eng | S |
| REL-04 | Generated `Info.plist` key coverage: orientations, capabilities, category, launch appearance | Bundle | Should-fix | Eng | S |
| REL-05 | iPad declared supported but never designed or verified | Bundle | **Blocker** | Owner / Des | M–L |
| REL-06 | Never built for Release, never archived, never signed | Bundle / Rel-eng | **Blocker** | Eng | M |
| REL-07 | No `PrivacyInfo.xcprivacy` | Privacy | Should-fix | Eng | S |
| REL-08 | Privacy nutrition labels undefined | Privacy | **Blocker** | Owner / ASC | S |
| REL-09 | No privacy policy | Privacy | **Blocker** | Legal / Owner | S–M |
| REL-10 | Export is gated behind Photos add-only permission with no fallback | Privacy / UX | Should-fix | Eng | S |
| REL-11 | Reconcile with the companion security and performance audits | Privacy | Nice-to-have | Eng | S |
| REL-12 | Twelve trademarked Stock Display Names ship in the Catalogue | Legal | **Blocker** | Owner / Legal | S–M |
| REL-13 | App name, subtitle, keywords and screenshots carry the same exposure | Legal | **Blocker** | Owner / Legal | S |
| REL-14 | No non-affiliation disclaimer anywhere | Legal | Should-fix | Legal / Eng | S |
| REL-15 | Curve Set provenance: digitised manufacturer datasheets, unlicensed | Legal | Should-fix | Legal / Owner | M |
| REL-16 | No `LICENSE`, no `NOTICE`, no copyright headers | Legal | Should-fix | Owner | S |
| REL-17 | PR-evidence screenshots contain Apple's simulator sample photograph | Legal | Should-fix | Eng | S |
| REL-18 | Approximation label appears at one naming site out of seven | Honesty | Should-fix | Eng | S |
| REL-19 | Unqualified Stocks are overwhelmingly `artistic`; accuracy unestablished | Honesty | Should-fix | Owner / Eng | M |
| REL-20 | Known grain defect zeroes Grain on all nine colour Profiles | Honesty / Quality | Should-fix | Eng | M |
| REL-21 | Minimum functionality (2.1) assessment | Guidelines | Nice-to-have | Owner | S |
| REL-22 | No monetisation of any kind; business model undecided | Guidelines | **Blocker** | Owner | S–L |
| REL-23 | Five synthetic studies ship in the middle of the Catalogue | Guidelines / UX | Should-fix | Owner / Eng | S |
| REL-24 | App forces dark mode; no light appearance | Design | Nice-to-have | Des | M |
| REL-25 | Accessibility: strong custom-control coverage, specific gaps | Accessibility | Should-fix | Eng / Des | M |
| REL-26 | English-only for v1: decision unrecorded, no `Localizable.strings` | Localisation | Nice-to-have | Owner | S |
| REL-27 | Copy: `Stock` vs mandated `Film Stock`, Britishisms, brand spelling | Copy | Should-fix | Des / Eng | S |
| REL-28 | Untagged photos are rejected with a developer-facing message | Robustness | Should-fix | Eng | S |
| REL-29 | Export peak memory is unbounded and unmeasured on device | Robustness | **Blocker** | Eng | M |
| REL-30 | Exported files accumulate in the temporary directory forever | Robustness | Should-fix | Eng | S |
| REL-31 | Raw engine error strings are shown to users verbatim | Robustness / Copy | Should-fix | Eng | M |
| REL-32 | SwiftData container has no failure handling and no migration plan | Robustness | **Blocker** | Eng | M |
| REL-33 | Reviewer edge-case matrix: permissions, cancel, iCloud, background, storage | Robustness | Should-fix | Eng | M |
| REL-34 | CI never builds Release, never archives, never signs | Rel-eng | Should-fix | Eng | M |
| REL-35 | No crash reporting, no dSYM plan | Rel-eng | Should-fix | Eng | S |
| REL-36 | No versioning scheme, no tags, no release checklist | Rel-eng | Should-fix | Eng | S |
| REL-37 | Signing, provisioning, TestFlight and ASC setup unverifiable | Rel-eng | **Blocker** | Owner / ASC | M |
| REL-38 | No store screenshots at any required size | Listing | **Blocker** | Des | M |
| REL-39 | No support URL | Listing | **Blocker** | Owner | S |
| REL-40 | Age rating, category, export compliance, description, keywords | Listing | **Blocker** | Owner / ASC | M |
| REL-41 | Catalogue is 210 MB; one Profile is 76 MB of duplicated payload | Guidelines / Quality | Should-fix | Eng | M |

---

# Findings

## A. Missing build and bundle artifacts

### REL-01 — No app icon and no asset catalogue

**Category:** Bundle · **Blocking:** Blocker · **Owner:** Design / Engineering · **Effort:** M

**Current state.** There is no `Assets.xcassets`, no `AppIcon.appiconset`, no `.png`
or `.pdf` icon source, and no icon-related build setting anywhere:

- `find . -iname "*.xcassets"` → **absent from the repo**.
- `FilmApp.xcodeproj/project.pbxproj:193-199` — the target's `PBXResourcesBuildPhase`
  has an empty `files = ( );` list. The app ships **no bundled resources of its own**;
  everything it draws is generated at runtime.
- `grep ASSETCATALOG FilmApp.xcodeproj/project.pbxproj` → **0 hits**. Neither
  `ASSETCATALOG_COMPILER_APPICON_NAME` nor `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`
  is set in either build configuration (`project.pbxproj:237-280`).
- `git status --porcelain --ignored` is empty, so nothing is hiding untracked on disk.

**Why it matters.** *(recalled)* An iOS app submitted to the App Store must contain an
app icon; the archive's `Info.plist` needs `CFBundleIconName`, which is emitted by
compiling an asset catalogue that contains an `AppIcon` set. Without it,
`xcodebuild -exportArchive` / App Store Connect upload validation fails outright
("Missing Info.plist value — a value for the key `CFBundleIconName` is required").
Guideline 2.3.8 also requires that icons be accurate and not misleading. Since
iOS 18, an icon set should additionally provide light, dark and tinted variants
*(recalled — re-verify the current required variants and sizes)*.

**What to do.**

1. Create `FilmApp/Assets.xcassets` with an `AppIcon.appiconset` (single 1024 × 1024
   source; add dark and tinted variants).
2. Add the asset catalogue as a file reference and to the target's
   `PBXResourcesBuildPhase` in `FilmApp.xcodeproj/project.pbxproj:193-199`, and set
   `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;` in **both** build configurations
   (`project.pbxproj:239-256` Release, `:261-278` Debug).
3. While the catalogue exists, also move the design tokens' hard-coded accent
   (`FilmApp/Design/Tokens.swift:133`, `Colour.oklch(0.74, 0.15, 55)`) into a
   `Color Set` if you want a global accent colour, and add
   `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`.
4. Design note: the icon must not use a Kodak, Fujifilm, Ilford, CineStill or Foma
   mark, trade dress, or a recognisable film canister/box likeness — see REL-13.

**Acceptance criteria.**

- `FilmApp/Assets.xcassets/AppIcon.appiconset/Contents.json` exists and is tracked.
- Both configurations set `ASSETCATALOG_COMPILER_APPICON_NAME`.
- A Release archive's `Info.plist` contains a non-empty `CFBundleIconName`.
- The Home-screen icon renders correctly in light, dark and tinted appearances.

**How to verify.** On a Mac:
`xcodebuild -project FilmApp.xcodeproj -scheme FilmApp -configuration Release -archivePath /tmp/Dye.xcarchive archive`
then
`/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" /tmp/Dye.xcarchive/Products/Applications/FilmApp.app/Info.plist`
and `xcrun altool --validate-app` (or Xcode Organizer → Validate App).

---

### REL-02 — No version and no build number

**Category:** Bundle · **Blocking:** Blocker · **Owner:** Engineering · **Effort:** S

**Current state.** `grep MARKETING_VERSION FilmApp.xcodeproj/project.pbxproj` → **0 hits**.
`grep CURRENT_PROJECT_VERSION` → **0 hits**. Neither build configuration
(`project.pbxproj:239-256`, `:261-278`) sets them, and
`GENERATE_INFOPLIST_FILE = YES` is on in both (`project.pbxproj:243`, `:265`).
There is no `Info.plist` in the repo to supply them instead — `find . -name "Info.plist"`
returns nothing, and `git tag` lists **zero tags**, so there is no version history either.

**Why it matters.** *(recalled)* With `GENERATE_INFOPLIST_FILE = YES`, Xcode synthesises
`CFBundleShortVersionString = $(MARKETING_VERSION)` and
`CFBundleVersion = $(CURRENT_PROJECT_VERSION)`. Unset, both expand to the empty
string. App Store Connect rejects an upload whose `CFBundleShortVersionString` is
missing, empty or not a period-separated numeric string, and requires
`CFBundleVersion` to increase monotonically for each upload of the same version.

**What to do.**

1. Set `MARKETING_VERSION = 1.0;` and `CURRENT_PROJECT_VERSION = 1;` in both
   configurations in `project.pbxproj`.
2. Decide and record the scheme in REL-36 (recommended: `MARKETING_VERSION` is the
   user-visible semantic version; `CURRENT_PROJECT_VERSION` is a monotonically
   increasing integer bumped on every TestFlight upload).
3. Consider driving `CURRENT_PROJECT_VERSION` from CI (`GITHUB_RUN_NUMBER`) so it can
   never be forgotten.

**Acceptance criteria.** A Release archive's `Info.plist` has a non-empty
`CFBundleShortVersionString` matching `^\d+(\.\d+){0,2}$` and a non-empty integer
`CFBundleVersion`.

**How to verify.**
`/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" …/FilmApp.app/Info.plist`
and the same for `:CFBundleVersion`, then a TestFlight upload that is accepted.

---

### REL-03 — The Home-screen name is `FilmApp`, not Dye

**Category:** Bundle · **Blocking:** Blocker · **Owner:** Engineering · **Effort:** S

**Current state.**

- `FilmApp.xcodeproj/project.pbxproj:249`, `:271` — `PRODUCT_NAME = "$(TARGET_NAME)";`
  and the single target is named `FilmApp` (`project.pbxproj:155`, `:159`), producing
  `FilmApp.app` (`project.pbxproj:58`).
- `grep INFOPLIST_KEY_CFBundleDisplayName project.pbxproj` → **0 hits**. There is no
  `CFBundleDisplayName` and no `CFBundleName` override anywhere.
- The bundle identifier *is* right: `PRODUCT_BUNDLE_IDENTIFIER = app.memoji.dye;`
  (`project.pbxproj:248`, `:270`).
- The word "Dye" reaches a user in exactly two places, and one of them is a system
  alert that will be titled "FilmApp":
  - `project.pbxproj:244`, `:266` —
    `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = "Dye saves your exported photos to your photo library.";`
  - `Sources/FilmEngine/Export/ExportedLUT.swift:52` — a `# Exported from Dye: …`
    comment written into every **Exported LUT**.
- The app has no title bar at all: `FilmApp/Editor/EditorView.swift:18` hides the
  navigation bar (`.toolbar(.hidden, for: .navigationBar)`), and the only
  `navigationTitle`s in the app are `"Settings"` and `"Glossary"`
  (`FilmApp/SettingsView.swift:21`, `:82`).

**Why it matters.** *(recalled)* Guideline 2.3.7 requires the app name on the device to
correspond to the name in the App Store listing. A store listing called "Dye" that
installs an icon labelled "FilmApp" is a metadata mismatch, and it is the kind of
thing a reviewer notices in the first ten seconds. It is also a plain user-trust
problem — a permission dialog titled "FilmApp" whose body says "Dye" reads as a
mis-signed or repackaged app.

**What to do.** Add
`INFOPLIST_KEY_CFBundleDisplayName = Dye;` to both configurations. Do **not** rename
`PRODUCT_NAME` or the target (that would churn the product path and the CI invocation
at `.github/workflows/ci.yml`, which builds `-scheme FilmApp`). Confirm the final
name against REL-13 (trademark) and REL-40 (name availability in App Store Connect)
before locking it in.

**Acceptance criteria.** The Home-screen label reads `Dye`; the Photos permission
alert title reads `Dye`; the App Store Connect app name is `Dye`.

**How to verify.**
`/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" …/FilmApp.app/Info.plist`,
then install on a device and read the Home screen and the add-to-Photos alert.

---

### REL-04 — Generated `Info.plist` key coverage

**Category:** Bundle · **Blocking:** Should-fix · **Owner:** Engineering · **Effort:** S

**Current state.** There is no `Info.plist` file in the repo; the plist is fully
synthesised from `INFOPLIST_KEY_*` build settings. The complete set present in
`FilmApp.xcodeproj/project.pbxproj` (identical in Release `:239-256` and Debug `:261-278`):

| Key | Value | Line |
| --- | --- | --- |
| `GENERATE_INFOPLIST_FILE` | `YES` | 243 / 265 |
| `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription` | `"Dye saves your exported photos to your photo library."` | 244 / 266 |
| `INFOPLIST_KEY_UIApplicationSceneManifest_Generation` | `YES` | 245 / 267 |
| `INFOPLIST_KEY_UILaunchScreen_Generation` | `YES` | 246 / 268 |
| `IPHONEOS_DEPLOYMENT_TARGET` | `17.0` | 247 / 269 |
| `PRODUCT_BUNDLE_IDENTIFIER` | `app.memoji.dye` | 248 / 270 |
| `TARGETED_DEVICE_FAMILY` | `"1,2"` | 255 / 277 |
| `SUPPORTED_PLATFORMS` | `"iphoneos iphonesimulator"` | 251 / 273 |

Everything else is **absent** (all verified as 0 hits in `project.pbxproj`):
`INFOPLIST_KEY_CFBundleDisplayName` (REL-03), `MARKETING_VERSION` /
`CURRENT_PROJECT_VERSION` (REL-02), `ASSETCATALOG_*` (REL-01),
`INFOPLIST_KEY_UISupportedInterfaceOrientations*`, `UIRequiredDeviceCapabilities`,
`ITSAppUsesNonExemptEncryption`, `LSApplicationCategoryType`,
`INFOPLIST_KEY_UIRequiresFullScreen`, `INFOPLIST_KEY_UIUserInterfaceStyle`,
`INFOPLIST_KEY_UIStatusBarStyle`, `CODE_SIGN_ENTITLEMENTS`, `INFOPLIST_FILE`.

**Permission strings are correct as they stand.** The app takes photos **in** through
`PhotosPicker`, which is out-of-process and needs no read authorisation
(`FilmApp/Editor/ActionRow.swift:46`, `FilmApp/Editor/EditorView.swift:184`,
`FilmApp/EditorModel.swift:145`), and writes **out** through
`PHPhotoLibrary.requestAuthorization(for: .addOnly)`
(`FilmApp/EditorModel.swift:322`) and `PHAssetCreationRequest`
(`FilmApp/EditorModel.swift:336-338`). So `NSPhotoLibraryAddUsageDescription` is the
right key and `NSPhotoLibraryUsageDescription` is correctly **not** declared —
declaring it would be worse, because it would prompt for full-library access the app
never uses. No other permission-gated framework is imported anywhere in shipping code.

**Why it matters.** *(recalled)*

- **Orientations.** With no `UISupportedInterfaceOrientations`, iOS permits every
  orientation the device supports. The editor only has two layouts — a
  landscape branch and a portrait branch chosen by `geometry.size.width > geometry.size.height`
  at `FilmApp/Editor/EditorView.swift:105` — and neither has been verified on device.
  An unhandled rotation into a broken layout is exactly what a reviewer trips over.
- **Launch screen.** `UILaunchScreen_Generation = YES` produces a plain launch screen
  with the **default system background**, which is white in light mode. The app then
  forces dark (`FilmApp/Editor/EditorView.swift:21`, `.preferredColorScheme(.dark)`)
  onto a `#050505` canvas (`FilmApp/Design/Tokens.swift:106`). The result is a white
  flash on every cold launch. Not a rejection, but it is the very first frame a
  reviewer sees.
- **Required device capabilities.** The engine hard-requires Metal
  (`Sources/FilmEngine/Renderer.swift:35-38` throws `"Metal is unavailable"`).
  Every iOS 17-capable device has Metal, so declaring `metal` in
  `UIRequiredDeviceCapabilities` is belt-and-braces rather than a fix — but it is
  cheap and it documents the requirement.
- **Encryption declaration.** See REL-40.
- **Category.** `LSApplicationCategoryType` is set in App Store Connect anyway, so
  this is cosmetic.

**What to do.** Add to both configurations:

```
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
INFOPLIST_KEY_UIRequiredDeviceCapabilities = metal;
INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;
INFOPLIST_KEY_UILaunchScreen_UIColorName = LaunchBackground;
INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.photography";
```

with a `LaunchBackground` colour set in the new asset catalogue matching
`Tokens.Palette.canvas` (`#050505`). If REL-05 resolves to iPhone-only, drop the
`_iPad` line and change `TARGETED_DEVICE_FAMILY` to `1`. Re-verify at submission
time that `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` is still an accepted
pass-through key *(recalled)*; if not, add a real `Info.plist`.

**Acceptance criteria.** The archived `Info.plist` contains every key above with the
intended values, and the app does not rotate into a layout nobody has approved.

**How to verify.** `plutil -p …/FilmApp.app/Info.plist` on the archive; rotate on a
device in every allowed orientation and screenshot each.

---

### REL-05 — iPad is declared supported but has never been designed or verified

**Category:** Bundle · **Blocking:** Blocker (for the store listing) · **Owner:** Owner / Design · **Effort:** M–L

**Current state.** `FilmApp.xcodeproj/project.pbxproj:255`, `:277` —
`TARGETED_DEVICE_FAMILY = "1,2";` (iPhone **and** iPad). Against that:

- The only responsive behaviour in the editor is a single width-vs-height branch at
  `FilmApp/Editor/EditorView.swift:105`, which caps the control column at
  `min(393, geometry.size.width * 0.46)` (`:108`) and the portrait deck at
  `maxWidth: 560` (`:115`) — numbers chosen for phone widths.
- No `horizontalSizeClass` / `UIUserInterfaceIdiom` check appears anywhere in
  `FilmApp/`.
- Every `#Preview` in the app is phone-shaped or unspecified
  (`FilmApp/Editor/DeckView.swift:132-150`, `FilmApp/Editor/EditorView.swift:273-282`,
  `FilmApp/ExportSheet.swift:335-339`, `FilmApp/ContactSheetView.swift:202-233`).
- Every screenshot in the repo is 1206 × 2622, i.e. a 6.3" iPhone
  (`docs/pr-evidence/identity-rail/*.png`, `docs/pr-evidence/ios-glass-toolbar/*.png`).
- `.github/workflows/ci.yml` builds only `-sdk iphonesimulator` with no destination,
  so no iPad simulator is ever exercised.

**Why it matters.** *(recalled)* Declaring iPad support has three consequences.
(1) App Store Connect will **require an iPad screenshot set** (13" iPad) before the
listing can be submitted. (2) An app that supports all four orientations and has a
launch screen is opted into iPad multitasking — Slide Over, Split View and Stage
Manager — so the editor will be resized to arbitrary widths nobody has laid out for.
(3) Guideline 2.1 / 4.0: an iPad build that is a stretched phone layout, or that
breaks in Split View, is a routine rejection.

**What to do.** This is a **decision, not a task**. Pick one:

- **Ship iPhone-only (recommended for v1).** Set `TARGETED_DEVICE_FAMILY = "1";` in
  both configurations. The app still runs on iPad in compatibility mode and needs no
  iPad screenshots. Cost: S.
- **Ship iPad properly.** Design an iPad layout (the landscape branch is a starting
  point but 393 pt of controls beside a 1000 pt canvas is not an iPad design), verify
  Slide Over / Split View / Stage Manager at every width, and produce a 13" iPad
  screenshot set. Cost: L.
- **Ship iPad but opt out of multitasking.** Keep family `1,2`, add
  `INFOPLIST_KEY_UIRequiresFullScreen = YES`, and still design and verify a
  full-screen iPad layout plus iPad screenshots. Cost: M. *(recalled: Apple has
  been progressively restricting `UIRequiresFullScreen`; re-verify it is still
  honoured before relying on it.)*

**Acceptance criteria.** `TARGETED_DEVICE_FAMILY` matches a decision recorded in this
document, and either (a) it is `1`, or (b) an iPad screenshot set exists and the
editor has been driven through portrait, landscape, Slide Over and a 1/2 and 2/3
Split View on a real iPad without clipped controls or unreachable hit targets.

**How to verify.** `xcodebuild -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'`
build and launch; drive the layouts listed above; capture the screenshots.

---

### REL-06 — The app has never been built for Release, archived or signed

**Category:** Bundle / Release engineering · **Blocking:** Blocker · **Owner:** Engineering · **Effort:** M

**Current state.**

- `.github/workflows/ci.yml` (the `app` job) runs exactly one build:
  `xcodebuild -project FilmApp.xcodeproj -scheme FilmApp -sdk iphonesimulator -configuration Debug -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO build`.
  **Debug. Simulator. Signing disabled.** No `archive`, no `-exportArchive`, no
  device destination, no `-configuration Release`.
- `README.md` documents the same simulator-only invocation.
- No `xcshareddata/xcschemes/` directory exists —
  `find FilmApp.xcodeproj -type f` returns **only** `project.pbxproj`. The scheme
  `xcodebuild -scheme FilmApp` uses is auto-created, so which configuration
  `archive` picks is not under version control.
- `git tag` → **zero tags**. Nothing has ever been cut as a release.
- The Release configuration differs from Debug in exactly one setting —
  `SWIFT_OPTIMIZATION_LEVEL = "-O"` (`project.pbxproj:252`) versus `"-Onone"` (`:274`).
  So the optimised build has never been compiled, let alone run.

**Two force-unwrapped bundle-resource lookups sit on the launch path**, and both
would be a trap-on-launch if SPM resource bundling behaves differently in a signed
Release archive than in a simulator Debug build:

- `Sources/FilmEngine/Profiles/Profile.swift:62-63` —
  `Bundle.module.url(forResource: "identity", withExtension: "json", subdirectory: "Calibration")!`
  followed by `try! JSONDecoder().decode(...)`. This backs `Profile.identity`
  (`Profile.swift:38`), which is reached on the **first frame**: the editor starts at
  `selectedStock = "identity"` (`FilmApp/EditorModel.swift:14`) and
  `EditorModel.profile` falls back to `.identity` (`:49`).
- `Sources/FilmEngine/Renderer.swift:44` —
  `Bundle.module.url(forResource: "Pipeline", withExtension: "metal", subdirectory: "Metal")!`,
  reached as soon as a photo is opened (`FilmApp/EditorModel.swift:152`).

Both resources come from `Package.swift:10`
(`.copy("Metal")`, `.copy("Profiles/Calibration")`, `.copy("Catalogue")`), which
produce a nested `FilmEngine_FilmEngine.bundle` inside the app. That has never been
verified inside a signed `.ipa`.

**Why it matters.** *(recalled)* Guideline 2.1 — an app that crashes on launch is
rejected immediately, and this is the single most likely way this app crashes on a
reviewer's device. Beyond that, an archive is where signing, entitlements,
provisioning, bitcode-era stripping, `-O` miscompiles and resource-bundle layout all
show up for the first time. None of them has been exercised.

**What to do.**

1. Commit a **shared scheme**: `FilmApp.xcodeproj/xcshareddata/xcschemes/FilmApp.xcscheme`
   with Archive set to the Release configuration.
2. Produce a Release archive locally and inspect the `.app` payload:
   confirm `FilmEngine_FilmEngine.bundle/Catalogue/*.filmprofile`,
   `.../Metal/Pipeline.metal` and `.../Calibration/identity.json` are all present.
3. Replace both force unwraps with a thrown `FilmError.invalid` so a packaging
   mistake surfaces as an error message rather than a trap. `Renderer.init` already
   `throws`; `Profile.identity` needs a `throws` variant or a safe fallback.
4. Install the Release build on a real device and run the reviewer path end to end
   (REL-33).
5. Add the archive step to CI (REL-34).

**Acceptance criteria.** A Release archive validates in Xcode Organizer, installs on
a physical device, launches to the welcome screen, opens a photo, renders a Stock and
completes an Export — with no force-unwrap traps and no missing resources.

**How to verify.**
`xcodebuild -project FilmApp.xcodeproj -scheme FilmApp -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/Dye.xcarchive archive`,
then `unzip -l` the exported `.ipa` and grep for the three resource paths, then
Organizer → Validate App, then TestFlight to a device.

---

## B. Privacy

### REL-07 — No `PrivacyInfo.xcprivacy`

**Category:** Privacy · **Blocking:** Should-fix · **Owner:** Engineering · **Effort:** S

**Current state.** `find / -name "*.xcprivacy"` → **absent from the repo and from
disk**. `git status --porcelain --untracked-files=all` is empty, so nothing is
hiding untracked.

An exhaustive sweep of shipping code (`FilmApp/` and `Sources/FilmEngine/`) found
**zero uses of any Apple required-reason API category**:

| Category | Result |
| --- | --- |
| File timestamp APIs | **None.** Every `creationDate` in the tree is either the app's own `ExportOptions` field (`Sources/FilmEngine/Export/ExportTypes.swift:57`, `:74`, `:78`) or `PHAssetCreationRequest.creationDate` (`FilmApp/EditorModel.swift:337`), which is PhotoKit asset metadata the app *writes*, not `NSFileCreationDate`. No `stat`, `getattrlist`, `attributesOfItem` or `NSURLContentModificationDateKey` anywhere. |
| System boot time APIs | **None.** No `systemUptime`, `mach_absolute_time`, `kern.boottime`. Timing uses `ContinuousClock` (`FilmApp/EditorModel.swift:318`, `:363`, `:411-413`, `:560`), which is not on the list. `ProcessInfo` is used only for `thermalState` (`FilmApp/EditorModel.swift:283`, `:591`; `Sources/FilmEngine/Export/ExportTypes.swift:83`). |
| Disk space APIs | **None.** No `volumeAvailableCapacity`, `statfs`, `NSFileSystemFreeSize`, `resourceValues`. |
| Active keyboard APIs | **None.** |
| User defaults APIs | **None.** No `UserDefaults`, `@AppStorage`, `@SceneStorage` or `NSUbiquitousKeyValueStore` anywhere in the repository. Persistence is SwiftData only (`FilmApp/PresetSheet.swift:5`, `FilmApp/FilmApp.swift:7`). |

`Sources/FilmEngine/Export/ExportDate.swift` — which the brief singled out — is
**pure EXIF/TIFF image metadata**, read from in-memory bytes via
`CGImageSourceCopyPropertiesAtIndex` (`ExportDate.swift:17`) and written via
`kCGImagePropertyExifDictionary` keys (`:50-67`). It touches no filesystem date API.

The one directory enumeration is
`Sources/FilmEngine/Profiles/ProfileCatalogue.swift:6`,
`FileManager.default.contentsOfDirectory(at:includingPropertiesForKeys: nil)` over
the app's own read-only bundle — `nil` keys means no timestamps or capacities are
fetched.

**There are also no third-party dependencies.** `Package.swift` declares no
`dependencies:` array at all, and `FilmApp.xcodeproj/project.pbxproj:326-331`
contains only an `XCLocalSwiftPackageReference` with `relativePath = .`. No
`XCRemoteSwiftPackageReference`, no `Package.resolved`. So there are no
third-party privacy manifests or signatures to aggregate.

**Why it matters.** *(recalled)* Apple requires a privacy manifest for apps that use
required-reason APIs, and for SDKs on Apple's "commonly used SDK" list. Since this
app uses none of them and vendors nothing, a manifest is **arguably not strictly
required** — this is the honest reading. But it is nearly free to add, it makes the
"no required-reason API" claim explicit and machine-checkable, and it feeds Apple's
generated privacy report. Add it. Re-verify the current obligation at submission
time; Apple has tightened this repeatedly *(recalled)*.

**What to do.** Create `FilmApp/PrivacyInfo.xcprivacy`, add it to the target's
`PBXResourcesBuildPhase` (`FilmApp.xcodeproj/project.pbxproj:193-199`, currently
empty), with:

```xml
<key>NSPrivacyTracking</key><false/>
<key>NSPrivacyTrackingDomains</key><array/>
<key>NSPrivacyAccessedAPITypes</key><array/>
<key>NSPrivacyCollectedDataTypes</key><array/>
```

**Acceptance criteria.** `PrivacyInfo.xcprivacy` is present at the root of the built
`.app`, and Xcode Organizer's "Generate Privacy Report" on the archive produces a
report with no accessed-API entries and no collected data types.

**How to verify.** `unzip -l Dye.ipa | grep xcprivacy`; Organizer → the archive →
Generate Privacy Report.

**Cross-reference.** The companion `docs/audits/security.md` reaches the same
conclusion independently as **SEC-05**. See REL-11.

---

### REL-08 — Privacy nutrition labels are undefined

**Category:** Privacy · **Blocking:** Blocker · **Owner:** Owner / App Store Connect · **Effort:** S

**Current state.** Nutrition labels live in App Store Connect, not the repo, so this
is **unverifiable from here** — but the answers are fully determined by what the code
does, and the code is unambiguous.

Verified data flow (derived here, because `docs/audits/security.md` is absent — REL-11):

- **No networking of any kind.** Zero `URLSession`, `URLRequest`, `import Network`,
  `NWConnection`, `CFNetwork`, `WKWebView` in shipping code, and zero `http://` /
  `https://` literals in `FilmApp/`, `Sources/FilmEngine/` or `project.pbxproj`.
  The single `http` string in the repo is an SVG XML namespace in the non-shipping
  Baker (`ProfileBaker/StepWedge.swift:110`).
- **No analytics, tracking, advertising or attribution.** Zero
  `AppTrackingTransparency`, `ATTrackingManager`, `ASIdentifierManager`,
  `advertisingIdentifier`, `AdSupport`, `identifierForVendor`; no Firebase,
  Crashlytics, Sentry, Amplitude, Mixpanel or Segment.
- **No third-party SDKs at all** (see REL-07).
- **Photos in** via out-of-process `PhotosPicker` (`FilmApp/EditorModel.swift:145`),
  which hands the app a single `Data` and never grants library access.
- **Photos out** via add-only PhotoKit
  (`FilmApp/EditorModel.swift:322`, `:335-338`).
- **On-device persistence only:** a temp file per Export
  (`FilmApp/EditorModel.swift:419-422`) and SwiftData **Presets**
  (`FilmApp/PresetSheet.swift:5-17`), which store a name, a Stock id, JSON-encoded
  `RenderSettings` and a timestamp — no photo bytes.
- **Permission-gated frameworks:** PhotoKit only. No CoreLocation, camera,
  microphone, contacts, HealthKit, keychain, `UIPasteboard` or `UIDevice`.
- The only `import os` (`FilmApp/EditorModel.swift:5`) is for
  `OSAllocatedUnfairLock` (`:309`) — there is no `Logger` or `OSLog` instance
  anywhere, so nothing is even written to the unified log.

**Why it matters.** *(recalled)* Every app must complete the App Privacy questionnaire
before a version can be submitted. Getting it wrong in either direction is a
problem: over-declaring invites scrutiny you do not need, and under-declaring is a
metadata misrepresentation.

**What to do.** In App Store Connect → App Privacy, answer:

- **Data collection:** "No, we do not collect data from this app."
- **Tracking:** No. (Hence no ATT prompt, correctly absent from the code.)
- Nothing else should be declarable.

If REL-22 ever adds analytics, a crash reporter (REL-35) or In-App Purchase, this
answer changes and so does REL-07's manifest — revisit both together.

**Acceptance criteria.** The App Privacy section reads "Data Not Collected", and it
is consistent with `PrivacyInfo.xcprivacy` and with the privacy policy (REL-09).

**How to verify.** App Store Connect → App Privacy; cross-check against the
Organizer-generated privacy report from REL-07.

---

### REL-09 — No privacy policy exists

**Category:** Privacy · **Blocking:** Blocker · **Owner:** Legal / Owner · **Effort:** S–M

**Current state.** Grepping the whole repository for `privacy policy`, `terms of use`,
`EULA` and `support url` returns **zero hits** in any `.md` or `.swift` file. There
is no policy document, no URL, and no in-app link. `FilmApp/SettingsView.swift`
contains only a Glossary (`:9-17`, `:82`) — there is no About, Legal, Credits or
Acknowledgements screen anywhere in the app.

**Why it matters.** *(recalled)* Guideline 5.1.1(i) and the App Store Connect
submission form require **every** app to supply a privacy policy URL, regardless of
whether it collects data. It is a hard field; the listing cannot be submitted
without it. It must be publicly reachable, must not 404, and its content must match
the nutrition labels (REL-08).

**What to do.**

1. Publish a privacy policy at a stable public URL under a domain you control
   (the bundle identifier `app.memoji.dye` suggests `memoji.app` — confirm you own it).
2. The content is short, because the truth is short: the app processes photographs
   entirely on device; it has no network access; it collects, transmits and stores
   no personal data; it saves exported images to the user's own photo library with
   the user's permission; **Presets** are stored locally on the device. Name a
   contact address and a last-updated date.
3. Enter the URL in App Store Connect.
4. Add an in-app link too — a `Link` row in `FilmApp/SettingsView.swift:10-16`
   beside Glossary — alongside the disclaimer from REL-14 and the attributions from
   REL-16. This is not required, but it is where users and reviewers look.

**Acceptance criteria.** A public URL returns a privacy policy that is consistent
with REL-08; the URL is entered in App Store Connect; the app has a Settings row
that opens it.

**How to verify.** Load the URL in a browser from a clean session; read it against
the App Privacy answers; tap the Settings row on device.

---

### REL-10 — Export is gated behind Photos permission with no fallback

**Category:** Privacy / UX · **Blocking:** Should-fix · **Owner:** Engineering · **Effort:** S

**Current state.** `FilmApp/EditorModel.swift:322-326`:

```swift
let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
try Task.checkCancellation()
guard authorization == .authorized || authorization == .limited else {
    throw FilmError.invalid("Photo not saved. Allow adding photos in Settings to save exports to Photos.")
}
```

The authorisation request happens **before** the render (`:327`) and before the file
is written (`:330`). If the user declines, the entire Export is abandoned: no
render, no file, no share sheet. The share affordance — `ShareLink(item: record.url)`
at `FilmApp/ExportSheet.swift:229` — is only reachable from the `.finished` state
(`ExportSheet.swift:33-34`), which is only reached after the Photos save succeeds
(`FilmApp/EditorModel.swift:345`).

The **Exported LUT** path is unaffected: `exportLUT()` (`FilmApp/EditorModel.swift:359-379`)
requests no permission and produces a shareable file.

**Why it matters.** *(recalled)* Guideline 5.1.1 requires that an app remain
functional, to the extent possible, when a user declines a permission it does not
strictly need. Saving to Photos is *a* destination, not *the* destination — the app
already writes the file to its own temporary directory and already knows how to
share it. A reviewer who taps "Don't Allow" on the very first permission prompt gets
an app whose headline feature is dead, which is both a bad first impression and an
avoidable 5.1.1 argument.

**What to do.**

1. Render and write the file first; request Photos authorisation only at the point of
   saving.
2. On denial (or `.denied` / `.restricted`), still transition to
   `.finished(ExportRecord(... savedDate: nil))` so the sheet shows the file and
   `ShareLink`, and show an inline note explaining that it was not added to Photos,
   with a button that opens Settings (`UIApplication.openSettingsURLString`).
3. Reword the message: "Photo not saved." reads as failure when in fact the export
   succeeded.

**Acceptance criteria.** With Photos add access denied, an Export still completes,
the finished sheet still appears with dimensions and file size, `Share` still works,
and the copy explains what did and did not happen.

**How to verify.** On device: Settings → Dye → Photos → None; run an Export; confirm
the finished sheet and the share sheet. Then grant access and confirm the asset
lands in Photos with the right creation date.

---

### REL-11 — Reconcile with the companion security and performance audits

**Category:** Privacy · **Blocking:** Nice-to-have · **Owner:** Engineering · **Effort:** S

**Current state.** `docs/audits/security.md` and `docs/audits/performance.md` are
**not in commit `c19bc12`**; they appeared as untracked files while this audit was
being written and were not used as a source for it (see *Method and limits*). The
data-flow inventory in REL-08 was therefore derived independently.

Reading only their headings, three of their findings reach the same conclusion as
findings here by an entirely different route, which is worth knowing because
independent agreement is stronger evidence than either alone:

| This audit | Companion | Agreement |
| --- | --- | --- |
| REL-30 — Exported files accumulate in `tmp/` forever | `security.md` **SEC-03** — *"Every successful Export leaves a full-resolution copy of the photo in the temporary directory forever"* | Same defect, same code (`FilmApp/EditorModel.swift:416-432`). SEC-03 frames it as a **privacy** problem — a full-resolution copy of the user's photograph persisting — which is a stronger argument than the storage one made here, and it may affect the REL-08 nutrition-label reasoning. Take SEC-03's framing. |
| REL-29 — Export peak memory is unbounded | `performance.md` **PERF-02** — *"Full-resolution decode holds ~1.45 GB of buffers at once"* | Same conclusion; PERF-02 has a measured-looking figure where REL-29 has an estimate. Use PERF-02's number. |
| REL-07 — No `PrivacyInfo.xcprivacy` | `security.md` **SEC-05** — *"No privacy manifest, and the app target's Resources build phase is empty"* | Identical, including the observation that the empty Resources phase (`FilmApp.xcodeproj/project.pbxproj:193-199`) is what would have to change. |

`security.md` also raises decode-robustness findings (SEC-01 pixel-count bounds,
SEC-02 finiteness between decode and `ImageWriter`, SEC-04 RAW extent conversion)
that this audit did not reach. All three are on the **photo-open path a reviewer
exercises immediately**, so they belong in REL-28's and REL-33's scope even though
they were found as security issues rather than as robustness issues.
`performance.md` PERF-01 (tile-plan overdraw above ~4 500 px) bears directly on
REL-29's Export behaviour.

**Why it matters.** Three audits written in parallel will drift. Where they agree the
finding is well established; where only one of them says something, that is the one
to check against the code.

**What to do.**

1. Merge the three audits' overlapping items into a single tracked list before any of
   them is worked, so nobody fixes REL-30 and SEC-03 twice.
2. Replace REL-08's data-flow inventory with a cross-reference to `security.md` once
   it is committed and the two have been reconciled.
3. Fold SEC-01, SEC-02 and SEC-04 into REL-28's decode-robustness work and REL-33's
   edge-case matrix.
4. Fold PERF-01 and PERF-02 into REL-29.
5. Re-check anything the three disagree on against the code, not against each other.

**Acceptance criteria.** `security.md` and `performance.md` are committed; a single
reconciled work list exists; REL-08 links to `security.md`.

**How to verify.** Read all three and confirm no finding appears twice with different
recommendations.

---

## C. Trademark and legal

> This section is a **risk assessment by a non-lawyer**, based on the repository and
> on recalled knowledge of App Review policy. It is not legal advice. Before
> submission, have counsel who handles trademark review the chosen option.

### REL-12 — Twelve Stocks ship under live commercial trademarks

**Category:** Legal · **Blocking:** Blocker (owner decision) · **Owner:** Owner / Legal · **Effort:** S–M

**Current state.** The **Catalogue** is 17 Profiles in
`Sources/FilmEngine/Catalogue/*.filmprofile`. Twelve carry a **Display Name** that is
a live commercial product name; five are synthetic studies:

| Profile `id` | Display Name | Rights holder | **Approximation** flag |
| --- | --- | --- | --- |
| `portra-400` | Kodak Portra 400 | Kodak Alaris | no |
| `portra-160` | Kodak Portra 160 | Kodak Alaris | no |
| `tri-x-400` | Kodak Tri-X 400 | Kodak Alaris | yes (1) |
| `t-max-100` | Kodak T-Max 100 | Kodak Alaris | yes (1) |
| `vision3-50d` | Kodak Vision3 50D | Eastman Kodak | no |
| `vision3-200t` | Kodak Vision3 200T | Eastman Kodak | no |
| `vision3-250d` | Kodak Vision3 250D | Eastman Kodak | yes (2) |
| `vision3-500t` | Kodak Vision3 500T | Eastman Kodak | yes (1) |
| `provia-100f` | Fujifilm Provia 100F | Fujifilm | no |
| `velvia-50` | Fujifilm Velvia 50 | Fujifilm | yes (1) |
| `cinestill-800t` | Cinestill 800T | CineStill Film | yes (8) |
| `fomapan-100` | Fomapan 100 Classic | Foma Bohemia | yes (2) |
| `study-c41` | Colour negative study (synthetic) | — | no |
| `study-e6` | Reversal study (synthetic) | — | no |
| `study-ecn2` | Motion picture study (synthetic) | — | no |
| `study-bw-silver` | Silver study (synthetic) | — | no |
| `study-bw-chromogenic` | Chromogenic study (synthetic) | — | no |

**Where the names surface in the shipping UI** — all read `profile.metadata.displayName`:

- `FilmApp/Editor/EditorPickers.swift:56` — the top **Film Stock** picker label.
- `FilmApp/Editor/EditorPickers.swift:29` — the browser sheet headline.
- `FilmApp/Editor/EditorPickers.swift:59` — the picker's VoiceOver value.
- `FilmApp/Editor/Filmstrip.swift:102`, `:112` — every filmstrip cell caption and
  its VoiceOver label.
- `FilmApp/ContactSheetView.swift:131`, `:143` — every **Contact Sheet** frame caption.
- `FilmApp/PresetSheet.swift:187` — every **Preset** row summary.
- `FilmApp/SettingsView.swift:45` — the Glossary's "Current stock · …" line.
- `FilmApp/Editor/Parameter.swift:305` — the Stock parameter readout.
- `Sources/FilmEngine/Export/ExportedLUT.swift:52`, `:72` — written into every
  **Exported LUT** the user shares (`# Exported from Dye: Kodak Portra 400, …` and
  the `.cube` `TITLE` line), so the name **leaves the device inside a user artefact**.

**Two brand references are hard-coded in Swift and are *outside* the Display Name
escape hatch:**

- `Sources/FilmEngine/Profiles/FilmProfile.swift:43-47` — the five **Contrast Filter**
  names: `"Yellow (Wratten 8)"`, `"Orange (Wratten 15)"`, `"Red (Wratten 25)"`,
  `"Green (Wratten 58)"`, `"Blue (Wratten 47)"`. **WRATTEN is a registered Eastman
  Kodak trademark.** These render at `FilmApp/Editor/ContrastFilterDiscs.swift:30`
  and `FilmApp/Editor/Parameter.swift:324-325`, and appear in `.cube` titles via
  `Sources/FilmEngine/Export/ExportedLUT.swift:75`.
- `FilmApp/Editor/Parameter.swift:578` — a user-facing hint literal containing
  `"Kodak's filter factor for this stock costs %.1f stops"`.

Also note `FilmApp/PresetSheet.swift:285`, a `#Preview` fixture using
`stockID: "kodachrome-64"` — Kodachrome is a live Kodak mark, and `#Preview` bodies
are compiled into the Release binary even though they never run.

**`CONTEXT.md` anticipated exactly this.** `CONTEXT.md:105-108` defines **Display
Name** as "the user-facing name of a Stock, **deliberately isolated as a single
Profile field so the whole Catalogue can be renamed for trademark reasons without
touching anything else**." That design decision is real and it works — but it has
never been exercised, and it does not cover the two hard-coded cases above.

**Why it matters.** *(recalled)*

- **Guideline 5.2.1 / 5.2.5** — apps must not use third-party trademarks or trade
  dress in a way that suggests endorsement, sponsorship or affiliation, and Apple
  will remove an app on a credible IP complaint. Guideline 5.2 explicitly places the
  burden on the developer to have the rights.
- Whether nominative fair use protects "Kodak Portra 400" as a *description of what
  is being emulated* is a genuinely contested question. It is more defensible when
  the name is used descriptively and sparingly with a disclaimer, and much less
  defensible when it is the product's headline feature, appears in the app name,
  subtitle, keywords and screenshots, and the app is monetised.
- The practical risk is not primarily App Review. It is a rights holder filing an
  Apple IP dispute at any time after launch — after which the app is pulled and the
  Catalogue has to be renamed under time pressure anyway.

**Options, with trade-offs and exactly which files change.**

**Option A — Rename the Catalogue to evocative, non-trademarked names (lowest risk).**

Change `"displayName"` in the twelve `Curves/*/stock.json` files:
`Curves/portra-400/stock.json:53`, `Curves/portra-160/stock.json:53`,
`Curves/tri-x-400/stock.json:17`, `Curves/t-max-100/stock.json:17`,
`Curves/vision3-50d/stock.json:53`, `Curves/vision3-200t/stock.json:53`,
`Curves/vision3-250d/stock.json:53`, `Curves/vision3-500t/stock.json:53`,
`Curves/provia-100f/stock.json:35`, `Curves/velvia-50/stock.json:31`,
`Curves/cinestill-800t/stock.json:3`, `Curves/fomapan-100/stock.json:17`.
Then re-run `Scripts/bake-catalogue.sh` **on a Mac** and commit the regenerated
`Sources/FilmEngine/Catalogue/*.filmprofile`. CI already enforces that the committed
Catalogue matches a fresh bake (`.github/workflows/ci.yml`, the "Bake and verify the
committed Catalogue" step runs `git diff --exit-code -- Sources/FilmEngine/Catalogue`),
so a rename that is not re-baked fails CI — good.

Also required, because they are not data:
- `Sources/FilmEngine/Profiles/FilmProfile.swift:43-47` — drop the Wratten numbers
  (`"Yellow"`, `"Orange"`, `"Red"`, `"Green"`, `"Blue"`, or "Yellow (K2)" style
  generic naming).
- `FilmApp/Editor/Parameter.swift:578` — remove `"Kodak's"`.
- `FilmApp/PresetSheet.swift:285` — change the fake missing-stock id.
- Store listing: name, subtitle, keywords, description, screenshots (REL-13).

The Profile **`id`** does **not** need to change (`portra-400` etc. remain stable
identifiers). Ids appear in `Sources/FilmEngine/Catalogue/*.filmprofile` filenames,
in `Tests/FilmEngineTests/Fixtures/GoldenImages/*.rgba16` filenames, in the
`.github/workflows/ci.yml` step-wedge loop's `case` patterns, and in **Preset**
records already saved on users' devices — renaming ids would break saved Presets
(`FilmApp/PresetSheet.swift:159`, `FilmApp/EditorModel.swift:439`). **Keep the ids.**
That said, ids *are* visible to users in one place: the Export filename is
`"\(profile.id).\(format.fileExtension)"` (`FilmApp/EditorModel.swift:330`), so an
exported file is literally named `portra-400.heic`. If Option A is chosen, change
the export filename to derive from the Display Name instead.

*Trade-off:* the app loses its single clearest signal to the audience that already
knows what Portra looks like. Discoverability and conversion both suffer. Mitigate
with descriptive copy that names a *look* rather than a product.

**Option B — Keep the names, add a prominent non-affiliation disclaimer (middle).**

Keep every Display Name; add REL-14's disclaimer to the app, the store description
and the privacy/support pages; remove the marks from the **app name, subtitle and
keywords**; never use a manufacturer's logo, packaging or colour trade dress in the
icon or screenshots; add `™`/`®` acknowledgement text.

*Trade-off:* materially reduces the "implies affiliation" argument but does not
eliminate takedown risk, and does nothing about the app being commercially built on
another company's marks if REL-22 adds monetisation. It is the option most apps in
this category actually take.

**Option C — Seek permission (lowest residual risk, lowest probability).**

Write to Kodak Alaris, Eastman Kodak, Fujifilm, CineStill and Foma. Expect no reply
from the large ones; CineStill and Foma are small enough that a reply is plausible.

*Trade-off:* months of latency, and a "no" is worse than never asking because it
documents knowledge.

**Option D — Ship Option A, keep an owner-provided mapping.** Rename the Catalogue,
and let the *store description* say in prose which real stocks inspired which looks
without putting marks in the app or the app name. This is the pragmatic compromise
and is what I would recommend for v1.

**Acceptance criteria.** One option is chosen and recorded in this document with a
date and the owner's initials; the twelve Display Names, the five Contrast Filter
names, `Parameter.swift:578`, the export filename and the store listing all match
that decision; the Catalogue is re-baked and CI is green.

**How to verify.** `grep -ao 'displayName[^,]*' Sources/FilmEngine/Catalogue/*.filmprofile`
lists the shipped names — check it against the decision. `strings` the built `.app`
and grep for each brand term. Screenshot every UI surface listed above.

---

### REL-13 — App name, subtitle, keywords and screenshots carry the same exposure

**Category:** Legal · **Blocking:** Blocker · **Owner:** Owner / Legal · **Effort:** S

**Current state.** No store listing copy exists in the repo at all — there is no
`fastlane/metadata`, no `store/`, no marketing copy file. So nothing is *wrong* yet;
this is a constraint on work not yet done.

What does exist that constrains it: `README.md:1` names the product `Dye`, and the
README's own body names Kodak, Fujifilm, CineStill, Foma, Vision3, Portra, Tri-X,
T-Max, Provia and Velvia 21 times. `docs/film-emulation-implementation-spec.md`
(42 brand hits; see `:160-166`, `:318`, `:353`, `:362`, `:370`) sketches a *future*
Catalogue naming Ilford HP5 Plus, FP4 Plus, Delta 3200, XP2 Super, Kentmere 100/400,
Fomapan 200/400, Kodak E100, Portra 800 and Velvia 100 — so the exposure grows if
that roadmap ships.

**Why it matters.** *(recalled)* Guideline 5.2.1 covers metadata as much as code, and
2.3.7 governs app-name accuracy. Putting a third-party mark in the **app name,
subtitle or keyword field** is the single most reliably rejected form of this: those
fields are indexed for search, so using a competitor's or a rights holder's mark
there is treated as trading on their name rather than describing your product. Apple
has historically rejected keyword stuffing with brand names outright.

**What to do.**

1. **App name:** `Dye` — no brand terms. Check availability in App Store Connect
   (REL-40); "Dye" is a common word and may be reserved.
2. **Subtitle (30 chars):** describe the craft, not the brands — e.g.
   `Analog film looks, modelled` or `Film response, physically`.
3. **Keywords (100 chars):** **do not** include Kodak, Portra, Tri-X, T-Max,
   Fujifilm, Provia, Velvia, CineStill, Vision3, Fomapan, Ilford, Wratten. Use
   generic terms: `film, analog, analogue, grain, halation, emulsion, negative,
   slide, darkroom, RAW, LUT`.
4. **Description:** if Option B or D is chosen in REL-12, the description is where
   the nominative reference belongs — descriptive, once, with the disclaimer
   (REL-14) immediately after.
5. **Screenshots:** whatever Display Names are on screen will be visible in them.
   Regenerate screenshots *after* REL-12 is decided, not before. Never use a
   manufacturer logo, film box, canister, or their brand colours.
6. **App icon:** same constraint (REL-01).

**Acceptance criteria.** The app name, subtitle and keyword fields contain no
third-party mark; the description and screenshots match the REL-12 decision; a
non-lawyer reading the listing would not conclude the app is made by, or licensed
by, a film manufacturer.

**How to verify.** Read the App Store Connect listing fields back; view the
screenshots at full size and check every visible caption.

---

### REL-14 — No non-affiliation disclaimer anywhere

**Category:** Legal · **Blocking:** Should-fix (Blocker if REL-12 resolves to Option B or D) · **Owner:** Legal / Engineering · **Effort:** S

**Current state.** Grepping the repository for `not affiliated`, `trademark`,
`disclaimer`, `™`, `®` returns nothing in any shipping source file or user-facing
string. There is no About screen, no Legal screen, no Acknowledgements —
`FilmApp/SettingsView.swift:9-17` offers a single `Glossary` row and nothing else.
The `.filmprofile` schema (`Sources/FilmEngine/Profiles/FilmProfile.swift`) has no
attribution or manufacturer field.

**Why it matters.** *(recalled)* Under Guideline 5.2, a clear, prominent statement
that the app is independent and unaffiliated is the standard mitigation for
nominative use of a mark. It does not make unlicensed use lawful, but it directly
addresses the "implies endorsement" limb, which is the one Apple applies.

**What to do.** If REL-12 resolves to keeping any brand reference:

1. Add a Legal / About row to `FilmApp/SettingsView.swift:10-16` containing:
   *"Dye is an independent app. It is not affiliated with, endorsed by, or sponsored
   by Eastman Kodak Company, Kodak Alaris, FUJIFILM Corporation, CineStill Film,
   FOMA BOHEMIA, or any other film manufacturer. All product names and trademarks
   are the property of their respective owners. Dye's renderings are physical
   models, not reproductions of any manufacturer's product."*
2. Put the same paragraph at the end of the App Store description and on the privacy
   policy / support page.
3. Add a line to the **Film Stock** browser sheet
   (`FilmApp/Editor/EditorPickers.swift:26-39`, which currently has room under the
   headline) so the disclaimer sits where the names actually are — this is also
   where REL-18's Approximation line belongs.

**Acceptance criteria.** The disclaimer is reachable in at most two taps from the
editor, is present in the store description, and names every rights holder whose
mark appears.

**How to verify.** Tap through Settings on device; read the store description.

---

### REL-15 — Curve Set provenance: digitised manufacturer datasheets, no licence

**Category:** Legal · **Blocking:** Should-fix · **Owner:** Legal / Owner · **Effort:** M

**Current state.** `Curves/` holds 15 `SOURCES.md` files and one
`PROCESS-SOURCES.md`. `Curves/README.md:44-46` makes citation an authoring
requirement, and the discipline is genuinely good: every measured CSV carries a
line-1 provenance comment naming publication and page — e.g.
`Curves/portra-400/neutral.red.csv:1` (`# Kodak E-4050, revised 2-16, page 4;
vector-path digitisation.`), `Curves/tri-x-400/density.csv:1` (`# Kodak F-4017…`),
`Curves/vision3-500t/granularity.csv:1` (`# Kodak H-1-5219t… nomograph`). Each
`SOURCES.md` pins the source PDF's SHA-256 (e.g. `Curves/portra-400/SOURCES.md:5-9`).
**No PDF or datasheet image is committed** — `find . -name "*.pdf"` returns nothing.
The repo therefore holds *numerical readings plus an extraction script*, not the
copyrighted figures themselves.

Three things need attention:

1. **The CineStill process curves come from a scraped storefront image.**
   `Curves/cinestill-800t/PROCESS-SOURCES.md:3-14` records that `process-cs41.csv`
   and `process-cs2.csv` were digitised from a 1200 × 1200 JPEG pulled from
   CineStill's Shopify CDN — a **marketing product page**, not a datasheet — with a
   pinned SHA-256, and notes that removing the Shopify resize suffix returns
   byte-identical data. `PROCESS-SOURCES.md:19` further records that one panel is
   "Cs2 overlaid on **Kodak's** curve chart", i.e. a third party's reproduction of
   Kodak artwork digitised at one further remove. **No licence, permission or
   terms-of-use reference appears in that file at all.** This is the weakest link in
   the chain.
2. **Only one source file states a rights position.**
   `Curves/contrast-filters/SOURCES.md:25-30` is exemplary: *"Attribution: Eastman
   Kodak Company, KODAK WRATTEN 2 Optical Filter curves. The repository contains
   independent numerical readings and an extraction script, not the source PDFs or
   reproduced chart artwork. **No open-content licence is claimed for Kodak's
   material**…"* The other thirteen `SOURCES.md` files record **no permission
   statement for the manufacturer material**.
3. **The CIE data is CC BY-SA 4.0 and the repo has no licence file.**
   `observer.csv` (byte-identical across nine Curve Sets) is CIE 1931 2° colour
   matching functions plus D65, DOIs `10.25039/CIE.DS.xvudnb9b` and
   `10.25039/CIE.DS.hjfjmt59`, attributed with checksums and a "Changes:" note at
   `Curves/portra-400/SOURCES.md:41-55` and equivalents in `portra-160/`,
   `provia-100f/`, `velvia-50/`, `vision3-500t/`, `vision3-50d/`, `vision3-200t/`,
   `vision3-250d/`, `fomapan-100/`. The attribution is properly done — but **CC BY-SA
   is copyleft**, the derived `observer.csv` is a share-alike derivative, and the
   repository publishes it with **no licence file at all** (REL-16). That obligation
   is currently undischarged.

For completeness and to the project's credit: six `SOURCES.md` files record a
*negative* attribution for Andrea Volpato's GPL-3.0 `spektrafilm` project
(`Curves/portra-400/SOURCES.md:86-93` and equivalents), each stating that no code,
profiles, LUTs, digitised curves or fitted parameters from it are incorporated. No
scanned book plates, forum scans or third-party measurement datasets are cited
anywhere.

**Why it matters.** Manufacturer datasheet charts are copyrighted figures. Extracting
numerical facts from a chart is a much stronger position than reproducing the chart —
facts are not copyrightable — and the project has deliberately kept to the former.
That is a real defence. But the CineStill storefront image is a different kind of
source, the CC BY-SA obligation is live, and none of this is written down anywhere a
lawyer or a rights holder would find it.

**What to do.**

1. Replace or re-source the CineStill process curves from a document CineStill
   publishes as technical data, or drop `cinestill-800t`'s process-specific curves
   and mark the Stock's provenance accordingly. At minimum, add a rights paragraph
   to `Curves/cinestill-800t/PROCESS-SOURCES.md` matching the one at
   `Curves/contrast-filters/SOURCES.md:25-30`.
2. Add that same rights paragraph to the thirteen `SOURCES.md` files that lack one,
   and make it a required section in `Curves/README.md:44-46`.
3. Discharge the CC BY-SA obligation: add a `LICENSE` (REL-16) and a `NOTICE`/
   `THIRD-PARTY-NOTICES.md` that reproduces the CIE attribution and states that
   `observer.csv` and its derivatives are CC BY-SA 4.0.
4. Have counsel confirm the "numerical facts extracted from a published chart"
   position before the app is monetised (REL-22).
5. Note that nothing in `Curves/` ships in the app — only the baked
   `Sources/FilmEngine/Catalogue/*.filmprofile` does. The exposure is on the public
   GitHub repository, not in the binary. That distinction is worth making to counsel.

**Acceptance criteria.** Every `SOURCES.md` carries a rights paragraph; the CineStill
source is replaced or its rights position stated; a `NOTICE` discharges CC BY-SA.

**How to verify.** `grep -L "Attribution" Curves/*/SOURCES.md` returns nothing.

---

### REL-16 — No `LICENSE`, no `NOTICE`, no copyright headers, no in-app attribution

**Category:** Legal · **Blocking:** Should-fix · **Owner:** Owner · **Effort:** S

**Current state.**
`find . -iname "LICENSE*" -o -iname "NOTICE*" -o -iname "COPYING*" -o -iname "*THIRD*PARTY*"`
→ **zero results**. No copyright header, no SPDX identifier, no `©` and no
"All Rights Reserved" in any `.swift`, `.metal`, `.py`, `.md`, `.json` or `.yml`
file. No About / Credits / Licences screen in the app
(`FilmApp/SettingsView.swift` offers only Glossary).
`Tests/FilmEngineTests/Fixtures/FilmReferences/manifest.json:7` has an unused
`"usageRights"` field, and `docs/film-emulation-implementation-spec.md:226`
sketches a `"rights"` schema — both unimplemented.

**Why it matters.** Two separate problems. (a) The repository is public with no
licence grant, so it is all-rights-reserved by default, while simultaneously
redistributing a CC BY-SA 4.0 derivative whose licence requires share-alike terms it
does not provide (REL-15). (b) *(recalled)* App Review does not require an
attributions screen, but Apple's own guidance and common practice expect
third-party notices to be reachable in-app, and any future dependency (a crash
reporter, REL-35) will bring licence obligations with it.

**What to do.**

1. Add a root `LICENSE` reflecting the intent — proprietary/all-rights-reserved for
   the app source is fine and is probably what you want, but it must be *stated*.
2. Add `NOTICE.md` (or `THIRD-PARTY-NOTICES.md`) covering: CIE datasets (CC BY-SA
   4.0, with the DOIs and the "Changes:" note), the manufacturer-datasheet rights
   paragraph from REL-15, and the trademark acknowledgements from REL-14.
3. Add an Acknowledgements row to `FilmApp/SettingsView.swift:10-16` rendering that
   text, alongside the privacy policy link (REL-09) and the disclaimer (REL-14).
4. Consider whether the repository should be public at all before launch — it
   currently exposes the whole Catalogue authoring pipeline and every `SOURCES.md`.
   That is an owner decision, not a defect.

**Acceptance criteria.** `LICENSE` and `NOTICE.md` exist at the repo root; the app has
an Acknowledgements screen containing the CIE attribution and the trademark notice.

**How to verify.** Read the two files; tap through Settings → Acknowledgements.

---

### REL-17 — PR-evidence screenshots republish Apple's simulator sample photograph

**Category:** Legal · **Blocking:** Should-fix · **Owner:** Engineering · **Effort:** S

**Current state.** Six 1206 × 2622 PNGs are committed and published on the public
GitHub repository: `docs/pr-evidence/identity-rail/{01-editor,02-stock-browser,03-output-browser}.png`
and `docs/pr-evidence/ios-glass-toolbar/{01-welcome,02-editor,03-largest-text}.png`.
All six show a magenta ice-plant flower field, which is **Apple's own iOS simulator
sample photograph**. `docs/pr-evidence/ios-glass-toolbar/README.md:14` discloses it —
*"The flower image is a sample already in the simulator's photo library"* — but
`docs/pr-evidence/identity-rail/` has **no README and no attribution at all**.

Everything else is clean:
- `Sources/FilmEngine/ContactSheetReference.swift:8-28` generates the **Contact
  Sheet Reference** procedurally: a 192 × 128 `LinearImage` built in a nested loop
  from a hardcoded `patches` array, an exponential exposure ramp, a checkerboard and
  a synthetic practical light. **No file is read, no image is decoded. There is no
  photograph and therefore no ownership question**, and this is the reference the
  Contact Sheet, the Filmstrip thumbnails and every Golden Image render against.
- `Tests/FilmEngineTests/Fixtures/README.md:1-12` confirms `linear-low.dng`,
  `linear-high.dng` and `untagged.png` are all generated
  (`Scripts/make-raw-fixtures.py`) and *"contain no manufacturer data or third-party
  images"*.
- `docs/audits/film-stock-accuracy-review/contact-sheet-{1,2,3}.png` are renders of
  the synthetic reference.
- The app bundle ships **no image assets at all**
  (`FilmApp.xcodeproj/project.pbxproj:193-199`, empty resources phase).

Separately, `design_handoff_dye_editor/Dye Editor - one rail.html` (3.4 MB, tracked)
embeds base64 PNGs carrying C2PA content-credential manifests that assert
AI-generated provenance. Not a rights problem, but it is a machine-readable
provenance assertion committed to a public repo — worth a conscious decision.

**Why it matters.** Apple's simulator sample media is Apple's copyrighted content,
licensed for use *within* Xcode and the simulator. Redistributing it as
full-resolution PNGs in a public repository is a stretch, and using it in **App Store
screenshots would be a clear problem** (REL-38) — reviewers do notice Apple's own
sample assets.

**What to do.**

1. Regenerate the PR evidence with a photograph you own, or delete the six PNGs and
   replace them with renders of the synthetic Contact Sheet Reference.
2. Add a `README.md` to `docs/pr-evidence/identity-rail/` recording the origin of
   whatever replaces them, matching the `ios-glass-toolbar` one.
3. Source and license the photographs for the store screenshots now (REL-38) —
   your own work, or an explicitly licensed stock image with the licence recorded.
   Model releases matter if any person is recognisable.
4. Decide whether `design_handoff_dye_editor/` belongs in the public repo.

**Acceptance criteria.** No Apple sample media remains in the repository; every
committed screenshot has a recorded origin; the store screenshots use imagery whose
rights are documented.

**How to verify.** Open each PNG and confirm the subject; read each directory README.

---

## D. Honesty of claims — the Approximation problem

### REL-18 — The Approximation label appears at one naming site out of seven

**Category:** Honesty · **Blocking:** Should-fix · **Owner:** Engineering · **Effort:** S

**Current state.** `CONTEXT.md:146-152` defines **Approximation** and states: *"A
Profile carrying any Approximation is an approximation, and **the app labels it as
one wherever it names the Stock**."* `Sources/FilmEngine/Profiles/FilmProfile.swift:103`
repeats the contract in a doc comment — *"The app says so wherever it names the
Stock"* — over
`FilmProfile.swift:104`: `public var isApproximation: Bool { provenance.values.contains(.approximation) }`.

**Exactly one surface honours it.** `FilmApp/Editor/Filmstrip.swift:102`:

```swift
Text((profile.metadata.isApproximation ? "Approx. · " : "") + profile.metadata.displayName)
```

plus its VoiceOver label at `Filmstrip.swift:112`
(`profile.metadata.displayName + approximation`, `:80`).

**The other six naming sites do not:**

| Site | Line | What it shows |
| --- | --- | --- |
| Top **Film Stock** picker — the single most prominent naming of a Stock | `FilmApp/Editor/EditorPickers.swift:56` | bare `displayName` |
| Picker VoiceOver value | `FilmApp/Editor/EditorPickers.swift:59` | bare `displayName` |
| Browser sheet headline, directly above the filmstrip | `FilmApp/Editor/EditorPickers.swift:29` | bare `displayName` |
| **Contact Sheet** frame caption and VoiceOver label | `FilmApp/ContactSheetView.swift:131`, `:143` | bare `displayName` |
| **Preset** row summary | `FilmApp/PresetSheet.swift:187` | bare `displayName` |
| Glossary "Current stock · …" | `FilmApp/SettingsView.swift:45` | bare `displayName` |
| **Exported LUT** header and `TITLE` | `Sources/FilmEngine/Export/ExportedLUT.swift:52`, `:72` | bare `displayName` |

`CONTEXT.md:416-421` records the decision as *"Resolved"* with *"the picker, the film
subtitle and a line under the picker all say so"*. At `c19bc12` the picker does not,
there is no film subtitle, and there is no line under the picker. The editor was
rebuilt since (`a080f4e` "Replace editor title bar with top-aligned glass pickers")
and **the label was lost in that redesign**. The only prose acknowledgement left in
the app is one clause buried in a Glossary entry
(`FilmApp/SettingsView.swift:108`: *"Some stocks approximate another emulsion; their
appearance is a simulation."*).

**Which Stocks are affected.** Seven of seventeen Profiles carry an Approximation
(read from the shipped `.filmprofile` headers):

| Profile | Approximated parameters |
| --- | --- |
| `cinestill-800t` | 8 — `mtf.channelResponse`, `mtf.cyclesPerMM`, `mtf.response`, `spectral.dyeDensity`, `spectral.dyeSeparation`, `spectral.exposureUnits`, `spectral.granularity`, `spectral.sensitivity` |
| `vision3-250d` | 2 — `spectral.dyeDensity`, `spectral.sensitivity` |
| `fomapan-100` | 2 — `spectral.contrastFilters`, `spectral.sensitivity` |
| `velvia-50` | 1 — `spectral.dyeDensity` |
| `vision3-500t` | 1 — `grain.densityExtrapolation` |
| `tri-x-400` | 1 — `spectral.contrastFilters` |
| `t-max-100` | 1 — `spectral.contrastFilters` |

Note the shipped **Provenance** map is a *superset* of the authored one: `vision3-500t`
has no `approximation` in `Curves/vision3-500t/stock.json` but gains
`grain.densityExtrapolation` during the **Bake**. So the label must be driven from
the Profile, as it is — not from the Curve Set.

Two nuances worth deciding on rather than ignoring:

- **Tri-X 400 and T-Max 100 are labelled `Approx.` solely because of
  `spectral.contrastFilters`**, a *shared* WRATTEN transmittance table, not anything
  about the Stock's own response. They are labelled as approximations even when no
  **Contrast Filter** is fitted. That over-labels, which devalues the signal on
  CineStill 800T where it genuinely matters.
- Conversely `portra-400` ships **31 `artistic` of 42 Provenance entries** and no
  Approximation at all, so it is presented completely unqualified. See REL-19.

**Why it matters.** *(recalled)* Guideline 2.3 requires that an app not include
misleading claims about itself. Naming a Stock is a claim; naming it with no
qualifier while the Profile's own data records that several of its inputs are stand-ins
is the kind of overstatement 2.3 is about. Independently of App Review, this is the
project's own stated contract and it is currently broken — which is a user-trust
problem and a `CONTEXT.md` violation.

**What to do.**

1. Restore the prefix at the top picker: `FilmApp/Editor/EditorPickers.swift:56` and
   the accessibility value at `:59`.
2. Add a line under the browser headline at `FilmApp/Editor/EditorPickers.swift:28-29`
   explaining what "Approx." means, in the same block as REL-14's disclaimer.
3. Add the prefix to `FilmApp/ContactSheetView.swift:131` and `:143`,
   `FilmApp/PresetSheet.swift:187` and `FilmApp/SettingsView.swift:45`.
4. Add a note to the **Exported LUT** header at
   `Sources/FilmEngine/Export/ExportedLUT.swift:52` — the file leaves the device and
   is the artefact most likely to be re-shared out of context.
5. Extract the prefix into one place (e.g. `FilmProfile.qualifiedDisplayName`) so
   the next editor redesign cannot silently lose it again, **and add a test that
   asserts every naming site uses it** — `Tests/` already asserts at the Profile
   codec seam (`CONTEXT.md:386-390`), so this belongs there.
6. Decide whether `spectral.contrastFilters` should make a whole Profile an
   Approximation, or whether the label should be scoped to the affected control.
   If you narrow it, update `CONTEXT.md:146-152` to match.

**Acceptance criteria.** Every surface that renders a Display Name renders the
qualifier for a Profile where `isApproximation` is true; a test fails if a new naming
site is added without it; `CONTEXT.md:416-421`'s "Resolved" note matches reality.

**How to verify.** Select CineStill 800T and screenshot the top picker, the browser
sheet, the Contact Sheet, a saved Preset row, the Glossary and an exported `.cube`
header. Run VoiceOver over the picker.

---

### REL-19 — Unqualified Stocks are overwhelmingly `artistic`, and accuracy is unestablished

**Category:** Honesty · **Blocking:** Should-fix · **Owner:** Owner / Engineering · **Effort:** M

**Current state.** Five of the twelve named Stocks — `portra-400`, `portra-160`,
`provia-100f`, `vision3-200t`, `vision3-50d` — carry **no Approximation at all**, so
under REL-18's rule they would still be presented with no qualifier whatsoever, as
`Kodak Portra 400`. Their shipped **Provenance** maps say something quite different:

| Profile | measured | artistic | approximation |
| --- | ---: | ---: | ---: |
| `portra-400` | 11 | **31** | 0 |
| `provia-100f` | 13 | **22** | 0 |
| `vision3-500t` | 13 | 30 | 1 |

For Portra 400, `measured` covers the characteristic curves, spectral sensitivity,
dye density, MTF, observer, paper, nominal ISO and format. `artistic` covers
`spectral.dirCouplers`, `spectral.scan`, `spectral.scanGamma`, `spectral.dyeSeparation`,
`spectral.dyeWidthNM`, `spectral.reconstruction`, `spectral.development`,
`spectral.enlarger`, all four `halation.*`, both `bloom.*`, all six `grain.*`,
`trueISO`, `balance`, `reciprocity.schwarzschildP` and every `colour.*` field —
i.e. the scanner, the DIR interactions, the grain, the halation and the print are all
judgement calls sitting on top of the measured curves.

The project's own accuracy audit
([`docs/audits/film-stock-accuracy.md`](film-stock-accuracy.md)) is unambiguous about
what that adds up to:

- `film-stock-accuracy.md:10-14` — *"The engine has a useful measured foundation, but
  **photographic accuracy is not yet established**… The scanner, dye separation,
  interlayer interactions, development variants and several spatial parameters still
  contain assumptions that can dominate the final appearance."*
- `film-stock-accuracy.md:76-93` — no independent photographic validation exists;
  the Step Wedge compares the shipped output against *the same model that baked it*,
  and the Golden Images *"contain no independent film reference"*.
- `film-stock-accuracy.md:203-205` — *"a stock with measured curves is not
  automatically a measured final emulation."*
- `Tests/FilmEngineTests/Fixtures/FilmReferences/manifest.json` is an empty
  placeholder: `"captures": []`, `"referenceWorkflow": "Pending controlled film
  captures; no photographic match claimed"`.
- `README.md` already says the five synthetic studies *"are intentionally not claims
  of stock accuracy"* — but says nothing equivalent about the twelve named ones.

One item in the accuracy audit has since been addressed and should not be re-reported:
`film-stock-accuracy.md:192-199` flagged that Vision3 250D's borrowed 50D data and
Velvia 50's borrowed Provia dye density were classified `artistic` and therefore not
disclosed. At `c19bc12` both are `approximation` in the shipped Profiles and both are
labelled. Good.

**Why it matters.** *(recalled)* Guideline 2.3 — accurate metadata; the app must not
make claims it cannot support. The risk here is not the Catalogue data, which is
carefully sourced and honestly annotated *inside the repo*. The risk is that **none
of that nuance reaches the user**, and that the store listing will almost certainly
want to say "physically accurate" or "modelled from manufacturer datasheets". The
first is unsupported by the project's own audit; the second is true and is the
stronger claim anyway.

**What to do.**

1. **Constrain the marketing claim.** Say "modelled from published manufacturer
   datasheets", "physically motivated", "a model of", never "accurate", "exact",
   "indistinguishable", "true to" or "the real Portra look". `README.md:3` already
   uses the right phrase — *"physically-motivated models"* — carry it into the store
   copy verbatim.
2. **Surface Provenance in the app.** The data is already there and per-parameter.
   A "How this Stock is modelled" row in the browser sheet, showing measured /
   artistic / approximation counts and which parameters fall where, converts the
   weakness into a differentiator. No other app in this category can show that.
3. **Consider a second qualifier tier.** `isApproximation` is binary. A Profile whose
   *response* is measured but whose *scanner, grain and halation* are artistic is a
   different thing from one whose sensitivity curve is borrowed. If you add a tier,
   add the term to `CONTEXT.md` first rather than inventing a synonym in passing.
4. Do **not** ship a comparison screenshot captioned as a match to real film until
   the held-out capture benchmark in `film-stock-accuracy.md:240-281` exists.

**Acceptance criteria.** No store copy, screenshot caption or in-app string claims
accuracy the accuracy audit does not support; the app can show a user where a given
Stock's numbers came from.

**How to verify.** Read the store description against
`docs/audits/film-stock-accuracy.md:10-14` line by line; tap the new Provenance row
for Portra 400 and CineStill 800T.

---

### REL-20 — A known grain defect zeroes Grain on all nine measured colour Profiles

**Category:** Honesty / Quality · **Blocking:** Should-fix · **Owner:** Engineering · **Effort:** M

**Current state.** `docs/audits/film-stock-accuracy.md:16-20` reports *"a **grain
calibration defect affecting all nine shipped measured/derived colour profiles**:
the renderer samples middle gray at the wrong cube coordinate. A CPU probe of the
committed profiles finds a **zero grain envelope at actual middle gray in every
one**."* The table at `film-stock-accuracy.md:49-59` lists all nine — Portra 160/400,
Provia 100F, Velvia 50, Vision3 50D/200T/250D/500T, CineStill 800T — with a grain
envelope of `0 / 0 / 0`. The cause is at
`Sources/FilmEngine/Renderer.swift`, `responseEntry`, sampling colour cubes at `0.18`
where the monochrome branch correctly applies `responseCoordinate`
(`film-stock-accuracy.md:32-46`).

That audit inspected `98ba1ec`; this audit is at `c19bc12`, and I could not run the
probe (no Swift, no Metal). `Sources/FilmEngine/Renderer.swift` still contains the
`grayDensity` machinery it describes (`Renderer.swift:26-29`). **Treat the defect as
open until the probe is re-run**: `python3 docs/audits/film-stock-accuracy-probe.py`.

Meanwhile the **Grain** control is prominent and makes explicit promises to the user:

- `FilmApp/Editor/Parameter.swift:634-635` — *"At this stock's own granularity."* /
  *"At %.0f%% of this stock's own granularity."*
- `FilmApp/SettingsView.swift:113` — *"Grain: Control film texture. 100% uses the
  stock's modelled intensity; zero removes it."*
- `README.md` — *"its own 0–200% control scales the Stock's published granularity."*

If the defect is live, all three statements are false for every colour Stock, and the
control does nothing on the nine Stocks a user is most likely to reach for.

**Why it matters.** *(recalled)* Guideline 2.1 — an app must be complete and function
as described; a headline control that silently does nothing is exactly what a
reviewer's five-minute pass finds. Guideline 2.3 — the in-app copy above is a claim.
And grain is arguably *the* reason people use a film emulator, so this is also the
largest quality gap in the product.

**What to do.**

1. Re-run `docs/audits/film-stock-accuracy-probe.py` against `c19bc12` to confirm the
   defect is still present.
2. Fix as `film-stock-accuracy.md:70-74` specifies: shape the colour reference
   coordinate the way the monochrome branch already does.
3. Add renderer tests over **shipped** colour Profiles with flat exposures around
   mid-grey, asserting a non-zero grain envelope, its location and its intensity
   scaling. The existing grain tests isolate the pass with identity cubes and miss
   the integration error (`film-stock-accuracy.md:72-74`).
4. Review and update the Golden Images on a Metal-capable Mac
   (`docs/golden-images.md`), which will all change.
5. Until it is fixed, do not put a grain claim in the store description.

**Acceptance criteria.** The probe reports a non-zero envelope for all nine colour
Profiles; a renderer test would fail if the coordinate regressed; a visual check at
Grain 0 % / 100 % / 200 % on Portra 400 shows a real difference.

**How to verify.** `python3 docs/audits/film-stock-accuracy-probe.py`; then on a Mac
`swift test --filter grain`; then on device, render Portra 400 at 0/100/200 % and
compare crops at 1:1 with the loupe.

---

## E. App Review Guideline compliance more broadly

### REL-21 — Minimum functionality (2.1): the app clears the bar

**Category:** Guidelines · **Blocking:** Nice-to-have · **Owner:** Owner · **Effort:** S

**Current state.** Recorded as a *positive* finding so it is not re-litigated. The app
is a substantial, original photo editor, not a wrapper or a filter pack:

- A thirteen-Pass Metal render graph with its own shaders
  (`Sources/FilmEngine/Renderer.swift:49-52` compiles 22 compute pipelines).
- Seventeen Profiles, a full-resolution tiled **Export** path
  (`Sources/FilmEngine/Export/Export.swift`), an **Exported LUT**
  (`Sources/FilmEngine/Export/ExportedLUT.swift`), RAW decode
  (`Sources/FilmEngine/ImageDecoder.swift:27-51`), EDR display
  (`FilmApp/FilmCanvas.swift:117-123`), **Presets** in SwiftData, a **Contact
  Sheet**, a hold-to-compare and a 1:1 loupe.
- Twenty-plus controls with real semantics, a Glossary
  (`FilmApp/SettingsView.swift:97-130`), and haptics.

**Why it matters.** *(recalled)* Guideline 4.2 (minimum functionality) and 4.3
(spam / duplicate) are the usual traps for "filter apps". Neither applies here on the
merits. The realistic 2.1 risks are elsewhere and are covered by REL-06 (crash on
launch from a Release-only packaging fault), REL-29 (low-memory termination during
Export) and REL-20 (a headline control that does nothing).

**What to do.** Nothing, beyond making sure the store description does not undersell
the app into looking like a filter pack.

**Acceptance criteria.** N/A — informational.

**How to verify.** N/A.

---

### REL-22 — There is no monetisation of any kind, and the business model is undecided

**Category:** Guidelines · **Blocking:** Blocker (a decision must exist) · **Owner:** Owner · **Effort:** S–L

**Current state.** Verified: the repository contains **no StoreKit, no In-App
Purchase, no subscription, no paywall, no price, no trial, no receipt validation and
no entitlement gate** of any kind. Grepping the whole tree for `StoreKit`,
`in-app purchase`, `subscription`, `paywall`, `restore`, `Product.` and `Transaction.`
returns nothing in any `.swift` file. The only hit anywhere is an unrelated sentence
in `docs/audits/film-stock-accuracy-research.md:111`. `Package.swift` has no
dependencies. No `.storekit` configuration file exists.

**Why it matters.** *(recalled)* This is not a defect — a free app with no IAP is the
simplest possible submission and skips the entire 3.1 ruleset. But the decision has
to be *made*, because it changes almost everything else in this audit:

- **Free, no IAP (simplest).** No StoreKit work, no restore-purchases requirement,
  no subscription disclosure, no Paid Apps agreement in App Store Connect. The
  App Privacy answer stays "Data Not Collected" (REL-08). **Recommended for v1.**
- **Paid up-front.** Requires the Paid Apps agreement, tax and banking in App Store
  Connect (REL-37), and it **raises the trademark stakes materially** — commercial
  use of another company's marks is far harder to defend as nominative fair use
  (REL-12).
- **Freemium with IAP / subscription.** Then Guideline 3.1.1 (all digital content
  through IAP), 3.1.2 (subscription disclosure — you must state price, duration,
  what is included, and link Terms and Privacy Policy *before* purchase), and the
  requirement for a working **Restore Purchases** control all apply. A reviewer will
  test restore on a second device; a missing or broken restore is a routine
  rejection. Add StoreKit 2, a paywall, receipt/`Transaction.currentEntitlements`
  checks, an entitlement gate around whatever is paid, and sandbox testing. This is
  an **L**, not an **M**.
  - If Stocks are the paid unit, the gate belongs in
    `Sources/FilmEngine/Profiles/ProfileCatalogue.swift:11-16` and
    `FilmApp/EditorModel.swift:139-143`, and it interacts with **Presets** — a
    Preset that names a Stock the user no longer owns must degrade gracefully. The
    machinery for that already exists (`FilmApp/EditorModel.swift:436-449`,
    `FilmApp/PresetSheet.swift:175`), which is convenient.
  - If Export resolution or format is the paid unit, the gate belongs in
    `FilmApp/ExportSheet.swift:113-124`.

**What to do.** Record the decision in this document before any other listing work
starts, because it determines REL-37 (agreements), REL-40 (pricing) and the risk
weighting of REL-12.

**Acceptance criteria.** A written decision with a date. If it is anything other than
"free, no IAP", a follow-up plan exists covering StoreKit 2, restore, disclosure and
sandbox testing.

**How to verify.** N/A — a decision, not a build artefact.

---

### REL-23 — Five synthetic studies ship in the middle of the Catalogue

**Category:** Guidelines / UX · **Blocking:** Should-fix · **Owner:** Owner / Engineering · **Effort:** S

**Current state.** `Sources/FilmEngine/Profiles/ProfileCatalogue.swift:6-7` loads the
Catalogue by sorting `.filmprofile` **filenames alphabetically**. The **Film Stock**
browser prepends `.identity` and shows that order unchanged
(`FilmApp/Editor/Filmstrip.swift:14`, `:53`). So a first-time user scrolling the
filmstrip sees, at indices 00–16:

`No Film Stock`, `Cinestill 800T`, `Fomapan 100 Classic`, `Kodak Portra 160`,
`Kodak Portra 400`, `Fujifilm Provia 100F`, **`Chromogenic study (synthetic)`**,
**`Silver study (synthetic)`**, **`Colour negative study (synthetic)`**,
**`Reversal study (synthetic)`**, **`Motion picture study (synthetic)`**,
`Kodak T-Max 100`, `Kodak Tri-X 400`, `Fujifilm Velvia 50`, `Kodak Vision3 200T`,
`Kodak Vision3 250D`, `Kodak Vision3 500T`, `Kodak Vision3 50D`.

Five slots in the middle of the browser — nearly a third of the Catalogue — are
synthetic calibration fixtures. `README.md` states *"The five synthetic studies are
intentionally not claims of stock accuracy"*, and their Display Names do say
"(synthetic)", but nothing in the UI explains what they are for.

Separately, `README.md` claims the picker is *"grouped by Process"*. It is not:
the filmstrip is one flat horizontal strip with a coloured process edge per cell
(`Filmstrip.swift:129-131`) and a four-item legend (`Filmstrip.swift:20-24`). The
README is stale on this point.

**Why it matters.** *(recalled)* Guideline 2.3 / 4.0 — shipping developer test
fixtures in the user-facing Catalogue reads as unfinished. A reviewer scrolling the
picker will hit five items whose names read as internal, and the ordering makes the
Catalogue look arbitrary. Not a rejection on its own, but it is the kind of thing
that colours a whole review.

**What to do.** Decide, and record:

- **Hide the studies from the shipping Catalogue** (recommended). They exist for
  Golden Images and Contact Sheet review, both of which load the Catalogue directly.
  Add a `visibility` field to the Profile schema, or filter in
  `FilmApp/EditorModel.swift:139-143` behind a debug flag. Cost: S.
- **Or keep them and give them a home:** a separate "Studies" section at the end of
  the browser with a one-line explanation.
- **Either way, control the order.** Alphabetical-by-filename is not a curated
  Catalogue. Add an explicit sort key to the Profile schema and lead with the
  strongest Stocks. This also lets you order the Contact Sheet and the store
  screenshots deliberately.
- Fix the "grouped by Process" claim in `README.md`.

**Acceptance criteria.** The first Stock a new user sees is the one you chose; the
studies are either absent or explained; `README.md` describes the picker accurately.

**How to verify.** Launch, open the browser, screenshot the full strip.

---

### REL-24 — The app forces dark mode; there is no light appearance

**Category:** Design · **Blocking:** Nice-to-have · **Owner:** Design · **Effort:** M

**Current state.** `FilmApp/Editor/EditorView.swift:21` — `.preferredColorScheme(.dark)`
on the root view, repeated at `FilmApp/SettingsView.swift:30` and
`FilmApp/ContactSheetView.swift:33`. The canvas is `#050505`
(`FilmApp/Design/Tokens.swift:106`). `Tokens.Palette.deck` *does* define a light
value (`Tokens.swift:107`, `dynamic(dark: .hex(0x0B0B0C), light: .hex(0xF4F2EE))`) and
several `#Preview`s render light (`FilmApp/Editor/EditorView.swift:278`,
`FilmApp/Editor/ParameterDial.swift:445`), so partial light support was built and is
then overridden globally. `INFOPLIST_KEY_UIUserInterfaceStyle` is **not** set, so the
lock is in code rather than in the bundle.

**Why it matters.** *(recalled)* Forcing dark mode is **allowed** and is normal for
photo editors — a neutral dark surround is a defensible colour-critical decision, not
a defect. Guideline 4.0 asks for platform-appropriate design, which this satisfies.
The costs are: a white launch-screen flash (REL-04), a system share sheet and Photos
picker that appear in the user's chosen appearance against a forced-dark app, and no
respect for a user who has deliberately chosen light.

**What to do.** Either (a) keep the lock and make it deliberate — fix the launch
background (REL-04) and note the decision here — or (b) honour the system appearance
and finish the light palette that `Tokens.swift:107` starts. (a) is the right call
for v1.

**Acceptance criteria.** The decision is recorded; there is no white flash on cold
launch; the app looks intentional beside a light-mode share sheet.

**How to verify.** Cold-launch on a device in light mode and record the first second;
open the share sheet and the photo picker.

---

### REL-41 — The Catalogue is 210 MB, and one Profile is 76 MB of duplicated data

**Category:** Guidelines / Quality · **Blocking:** Should-fix · **Owner:** Engineering · **Effort:** M

**Current state.** `Sources/FilmEngine/Catalogue/` is **210 MB** and all of it ships:
`Package.swift:10` declares `.copy("Catalogue")`, and
`Sources/FilmEngine/Profiles/ProfileCatalogue.swift:12` loads it from
`Bundle.module.resourceURL`.

| Profile | Size |
| --- | ---: |
| `cinestill-800t` | **76.0 MB** |
| `vision3-500t`, `vision3-250d`, `vision3-50d`, `vision3-200t`, `portra-400`, `portra-160` | 18.9 MB each |
| `provia-100f` | 10.5 MB |
| `velvia-50` | 8.4 MB |
| `study-ecn2`, `study-c41`, `study-e6` | 0.55 MB each |
| `t-max-100`, `fomapan-100`, `tri-x-400` | ≈ 17 KB each |
| `study-bw-silver`, `study-bw-chromogenic` | ≈ 3.7 KB each |

`README.md` states CineStill 800T ships *"byte-identical Colour Cubes"* to Vision3
500T, so roughly 57 MB of that 76 MB is a duplicate of another Profile already in the
bundle. The Profile format already supports lazy payload loading
(`Sources/FilmEngine/Profiles/Profile.swift:40-56`, `case .file(url, offset, entries)`)
and derivation (`derivedFrom`, `FilmApp/EditorModel.swift:59-62`), so the machinery
for sharing exists and is simply not used for payloads.

**Why it matters.** *(recalled)* A ≈ 220 MB download is not a rule violation — the
iOS app size limit is far higher — but it sits above the cellular-download threshold
at which iOS warns or asks the user to wait for Wi-Fi *(recalled; re-verify the
current threshold, which Apple has raised more than once)*. Practically it costs
installs, it costs 210 MB of the user's storage, and it makes every TestFlight
upload slow. It also compounds REL-29: the bundle is on disk, not in memory, but a
210 MB resource directory next to a multi-hundred-megabyte Export is a device under
pressure.

**What to do.**

1. Deduplicate CineStill 800T against Vision3 500T. The container already indexes
   payloads by name with offsets (`Profile.swift:45-51`); a cross-Profile payload
   reference, or simply loading the parent's file for shared payloads via
   `derivedFrom`, removes ~57 MB for a small amount of Baker and loader work.
2. Audit `colour.lutSize` — the large Profiles carry 65³ cubes per Development Offset
   *and* per Print variant (`Curves/portra-400/stock.json:14-40`). Measure whether
   33³ is perceptually distinguishable for the Print variants; halving the lattice
   edge is an 8× saving.
3. Consider On-Demand Resources or a first-run download for the Stocks beyond a
   core set — but only after REL-22, since that is also the natural shape of a
   freemium Catalogue.
4. Whatever you do, re-run `Scripts/bake-catalogue.sh` and the Golden Images.

**Acceptance criteria.** The installed app is materially under the cellular-download
threshold, or a conscious decision is recorded that it is not.

**How to verify.** Build a Release archive and read the App Store Connect
"App Store File Sizes" report after upload; `du -sh` the `.app` payload locally.

---

## F. Accessibility

### REL-25 — Custom-control coverage is strong; the gaps are specific

**Category:** Accessibility · **Blocking:** Should-fix (not a rejection risk) · **Owner:** Engineering / Design · **Effort:** M

**Ranked honestly:** accessibility is **not** blocking for App Store approval
*(recalled — Apple does not gate approval on VoiceOver or Dynamic Type)*. It is a
real quality gap and a differentiator, and it is in much better shape here than the
brief anticipated. The custom-drawn controls the brief expected to be the likely gaps
are, with one exception, the best-covered part of the app.

**What is already done — verified, not assumed.**

| Control | Evidence |
| --- | --- |
| **ParameterDial** (custom `Canvas` tape) | `accessibilityElement()`, label, value and `accessibilityAdjustableAction` at `FilmApp/Editor/ParameterDial.swift:27-30`; the adjust handler at `:99-116` quantises on the *same* grid as the drag via a shared `TrackMap.settle` (`:211-217`) and fires the same detent/limit haptics. The decorative track is `accessibilityHidden(true)` (`ParameterDialTrack`, `:309`). |
| **ParameterRail** (custom scroll rail) | A full `accessibilityRepresentation` at `FilmApp/Editor/ParameterRail.swift:44-56` replacing the rail with an adjustable element plus one button per parameter, each labelled `"<stage>, <name>"` with the live readout as its value and `.isSelected`. Separators are hidden (`:65`). |
| **Filmstrip** | Per-cell label, `developing` value and `.isSelected` at `FilmApp/Editor/Filmstrip.swift:112-114`; container label at `:59`; sprockets hidden at `:153`. It is also the **only** surface that carries the Approximation qualifier (`:80`, `:112`) — see REL-18. |
| **ContrastFilterDiscs** | Label, value and `.isSelected` per disc at `FilmApp/Editor/ContrastFilterDiscs.swift:30-32`. |
| **OutputStageCards** | Label, a descriptive value and `.isSelected` at `FilmApp/Editor/OutputStageCards.swift:39-41`. |
| **EditorPickers** | Label, value and hint on both pickers at `FilmApp/Editor/EditorPickers.swift:58-60`, `:67-70`. |
| **Canvas** | The Metal view is wrapped and labelled at `FilmApp/Editor/EditorView.swift:130-134`, the gesture overlay is hidden (`FilmApp/Editor/CanvasView.swift:62`), and hold-to-compare and the 1:1 loupe — both gesture-only — are exposed as named `accessibilityAction`s at `FilmApp/Editor/EditorView.swift:222-226`, with an `.id()` refresh so SwiftUI does not cache the stale action name (`:228-230`). |
| **Reset** | The long-press/double-tap reset is exposed as a named action at `FilmApp/Editor/DeckView.swift:80`. |
| **Reduce Motion** | Honoured in seven places: `FilmApp/Editor/DeckView.swift:62`, `:86`; `FilmApp/Editor/ParameterRail.swift:38`, `:87`; `FilmApp/Editor/Filmstrip.swift:111`; `FilmApp/Editor/CanvasView.swift:92`; `FilmApp/Editor/ActiveControl.swift:38-39`. |
| **Reduce Transparency** | `FilmApp/Design/Surfaces.swift:531-537` — `EditorGlass` substitutes an opaque `#1C1C20` capsule at any OS when `accessibilityReduceTransparency` is on, ahead of the iOS 26 `glassEffect` branch and the iOS 17–18 `.ultraThinMaterial` fallback. |
| **Increase Contrast** | `colorSchemeContrast` thickens the glass border at `Surfaces.swift:536`, `:540`, `:543`. |
| **Dynamic Type** | The deck grows rather than clips (`FilmApp/Editor/DeckView.swift:31`, `:44`); the action row switches to a native `Menu` at accessibility sizes (`FilmApp/Editor/ActionRow.swift:19-34`) with a `@ScaledMetric` label height (`:82`, `:97`); the pickers wrap to two lines (`FilmApp/Editor/EditorPickers.swift:78`) and reflow via `ViewThatFits` (`:11-20`); the Contact Sheet widens its grid (`FilmApp/ContactSheetView.swift:93`); the readout shrinks (`FilmApp/Editor/ActiveControl.swift:35`). `docs/pr-evidence/ios-glass-toolbar/03-largest-text.png` is evidence this was actually looked at, and there are dedicated `#Preview`s at `accessibility5` (`DeckView.swift:141-150`, `ActionRow.swift:121-126`). |
| **Hit targets** | `Tokens.Metrics.minimumHitTarget` is applied throughout: `ParameterDial.swift:26`, `Filmstrip.swift:32`, `ContrastFilterDiscs.swift:26`, `EditorPickers.swift:87`, `ContactSheetView.swift:51`, `EditorView.swift:78`, `:188`; rail pucks are 56 × 56 at a 76 pt pitch (`ParameterRail.swift:81`, `Tokens.swift:169-170`); the bypass toggle is 44 × 44 (`ActiveControl.swift:60`). |

**The actual gaps.**

1. **`FilmApp/PresetSheet.swift` is the weakest surface.** The row combines children
   (`:228`) and exposes a `developing` value (`:229`), but there is no
   `accessibilityLabel`, so VoiceOver reads a concatenation of the name, the summary
   line and the unavailable warning. More importantly, **delete is swipe-only**
   (`:114-117`) — there is no `accessibilityAction(named: "Delete")`, so a VoiceOver
   user cannot delete a Preset at all. The `TextField` at `:61` has a placeholder but
   no label.
2. **The Approximation qualifier is missing from six naming sites**, including two
   VoiceOver values (`EditorPickers.swift:59`, `ContactSheetView.swift:143`). See
   REL-18.
3. **Colour contrast falls below 4.5:1 in two token roles** (approximate values,
   computed by hand here — verify with a real contrast checker):
   - `Tokens.Palette.textQuaternary` = white at 0.40 over the `#0B0B0C` deck
     (`Tokens.swift:144`, `:107`) ≈ **3.7:1**. Used for the "No presets yet" empty
     state (`PresetSheet.swift:99`) and a disc border (`Surfaces.swift:563`).
   - `Tokens.Palette.textDisabled` = white at 0.30 (`Tokens.swift:145`) ≈ **2.6:1**.
     Legitimate for disabled controls, but it is also used for the Contact Sheet's
     informational legend (`ContactSheetView.swift:154`, "N stocks · N processes"),
     which is not disabled.
   - `Tokens.Palette.textTertiary` at 0.55 (`Tokens.swift:143`) ≈ 6.2:1 — fine.
   - The rail's stage separators are `.white.opacity(0.3)` at 8 pt monospaced
     (`ParameterRail.swift:62-63`) — very small and very low contrast, though they
     are correctly `accessibilityHidden`.
4. **`FilmApp/SettingsView.swift` has zero accessibility calls.** It is standard
   `List` / `NavigationLink` so it inherits sensible behaviour, but the Glossary's
   long explanations are not marked up in any way.
5. **`FilmApp/FilmCanvas.swift` has zero accessibility calls.** Correct — the parent
   labels it (`EditorView.swift:130-134`) — but the thumbnail instances inside
   `Filmstrip.swift:122`, `ParameterRail.swift:111`, `OutputStageCards.swift:21`,
   `PresetSheet.swift:235` and `ExportSheet.swift:203` rely on their parents doing
   the same, and `ExportSheet.swift:210` is the only one that explicitly hides it.
6. **Nothing is verified.** No accessibility test, no snapshot test, no CI check.
   `.github/workflows/ci.yml` runs `Scripts/check-dial-mapping.py` for the rail but
   nothing for VoiceOver or Dynamic Type.

**Why it matters.** *(recalled)* Not an approval gate. It matters because a photo
editor with genuinely adjustable custom dials under VoiceOver is rare and worth
saying so, and because the gaps above are cheap to close relative to what has already
been built.

**What to do.**

1. Give `PresetRowView` an explicit `accessibilityLabel` combining name and summary,
   and add `accessibilityAction(named: "Delete")` beside the swipe action
   (`PresetSheet.swift:114-117`). Label the `TextField`.
2. Apply REL-18's qualifier everywhere, including the two VoiceOver values.
3. Raise `textQuaternary` to ≥ 0.55 alpha for informational text, or stop using
   `textDisabled` for the Contact Sheet legend.
4. Add one automated check: a snapshot test at `.accessibility5` for the deck and
   the browser sheet, run in the `app` CI job.
5. Do a manual VoiceOver pass on device covering: welcome → picker → browse Stocks →
   adjust a dial → compare → loupe → save a Preset → delete a Preset → Export.

**Acceptance criteria.** Every interactive element has a label; every gesture-only
affordance has an accessibility action; no informational text is below 4.5:1;
the app is fully operable with VoiceOver at `accessibility5`.

**How to verify.** Xcode Accessibility Inspector audit on each screen; VoiceOver on
device for the flow above; a contrast checker on the token pairs listed.

---

## G. Localisation and copy

### REL-26 — English-only for v1: acceptable, but record the decision

**Category:** Localisation · **Blocking:** Nice-to-have · **Owner:** Owner · **Effort:** S

**Current state.** Confirmed absent: no `Localizable.strings`, no `.xcstrings` string
catalogue, no `.lproj` directory anywhere. `FilmApp.xcodeproj/project.pbxproj:173-178`
declares `developmentRegion = en;` and `knownRegions = (en, Base);`.
`SWIFT_EMIT_LOC_STRINGS` is not set. Every user-facing string is a Swift literal —
the Glossary alone is 33 entries of prose at `FilmApp/SettingsView.swift:97-130`, and
`FilmApp/Editor/Parameter.swift:540-720` holds around eighty formatted caption
strings.

**Why it matters.** *(recalled)* English-only is entirely acceptable; App Store
Connect simply lists English as the only localisation and the app appears worldwide.
There is no guideline requiring localisation. The reason to record the decision is
that retrofitting is much more expensive than starting with a string catalogue, and
`Parameter.swift`'s captions use `String(format:)` with positional arguments that
will need reordering support when it happens.

**What to do.**

1. Record: **v1 ships English (en) only.** Set the App Store Connect primary language
   to English (U.S.) — see REL-27 on spelling.
2. Cheap insurance for later: add a `Localizable.xcstrings` String Catalogue and set
   `SWIFT_EMIT_LOC_STRINGS = YES` now, so new strings are captured as they are
   written even if nothing is translated.

**Acceptance criteria.** The decision is written down; App Store Connect lists
English only.

**How to verify.** N/A — a decision.

---

### REL-27 — Copy: `Stock` vs the mandated `Film Stock`, Britishisms, brand spelling

**Category:** Copy · **Blocking:** Should-fix · **Owner:** Design / Engineering · **Effort:** S

**Current state.**

**1. A `CONTEXT.md` violation.** `CONTEXT.md:40-43` mandates: *"User-facing controls
use **Film Stock**. The top picker shows 'Film Stock' until a stock is selected…
The neutral browser option is **No Film Stock**."* Compliance is partial:

| Site | Line | Text | Verdict |
| --- | --- | --- | --- |
| Top picker, unselected | `FilmApp/Editor/EditorPickers.swift:56` | `"Film Stock"` | correct |
| Picker VoiceOver label | `FilmApp/Editor/EditorPickers.swift:58` | `"Film Stock"` | correct |
| Browser sheet headline | `FilmApp/Editor/EditorPickers.swift:28` | `"Film Stock"` | correct |
| Identity Profile Display Name | `Sources/FilmEngine/Profiles/Calibration/identity.json` | `"No Film Stock"` | correct |
| Glossary entry title | `FilmApp/SettingsView.swift:108` | `"Film Stock"` | correct |
| **Rail parameter name** | `FilmApp/Editor/Parameter.swift:303` | **`"Stock"`** | **wrong** — this is the name VoiceOver reads for the rail puck (`ParameterRail.swift:51`, `:90`) |
| **Its fallback readout** | `FilmApp/Editor/Parameter.swift:305` | **`"Stock"`** | **wrong** |
| **Debug parameter picker** | `FilmApp/Editor/Parameter.swift:734` | **`Picker("Stock", …)`** | wrong (though `#Preview`-only) |
| Glossary body | `FilmApp/SettingsView.swift:99`, `:103` | `"The Stock header stays visible"`, `"Compare the stocks"` | inconsistent casing |
| Welcome copy | `FilmApp/Editor/EditorView.swift:175` | `"explore film stocks"` | lower-case; acceptable in prose but decide |

The screenshot at `docs/pr-evidence/identity-rail/02-stock-browser.png` shows the
pre-`cde0c7f` state (`"Stock"` headline, `"Identity"` cell) and is therefore stale
evidence — see REL-38.

**2. Spelling is consistently British.** `colour`, `grey`, `neutralise`, `modelled`,
`digitised`, `emphasised` throughout — including in visible UI: `"Colour"` as an
Export section label (`FilmApp/ExportSheet.swift:63-64`), `"Colour space"` in the
Glossary (`SettingsView.swift:127`), `"Mid-grey and everything below it…"`
(`Parameter.swift:661`), `"…so mid-grey comes back neutral"` (`:700`),
`"colour intensity"` (`SettingsView.swift:124`). The engine's *API* is British too
(`RenderSettings.Output`, `ColourCube`, `contrastFilter`), and `CONTEXT.md` itself is
written in British English.

This is **not a defect** — it is a choice — but it is a choice nobody has made. The
largest App Store market for a paid photo tool is the U.S., and `colour` / `grey`
read as foreign there. Changing it later is a large diff across
`Parameter.swift`, `SettingsView.swift` and `ExportSheet.swift`.

**3. Brand spelling.** The Display Name is `Cinestill 800T`
(`Curves/cinestill-800t/stock.json:3`); the company styles itself **CineStill** with
a capital S. If REL-12 resolves to keeping the names, spell them the way the rights
holder does — getting a mark's own capitalisation wrong is a small thing that reads
badly and weakens a nominative-use argument.

**4. Two user-facing strings contain internal jargon.** `Parameter.swift:578`
(`"Kodak's filter factor…"`, also REL-12) and the raw engine errors covered by REL-31.

**Why it matters.** *(recalled)* Guideline 2.3.7 / 4.0 — metadata and UI should be
consistent and polished. Nothing here is a rejection. The `CONTEXT.md` violation
matters because the glossary is the project's binding vocabulary and the rail is a
primary surface.

**What to do.**

1. Change `FilmApp/Editor/Parameter.swift:303` and `:305` to `"Film Stock"` and
   `:734` likewise. Normalise the Glossary body copy.
2. Decide the spelling variant and record it. If U.S.: change the *user-facing*
   strings only (`ExportSheet.swift:63-64`, `SettingsView.swift:124`, `:127`,
   `Parameter.swift:661`, `:700` and the rest of the `Parameter.swift` captions) and
   leave the engine API and `CONTEXT.md` alone — the API is not user-facing and
   churning it would be pointless. Set the App Store Connect primary language to
   match.
3. Fix `Cinestill` → `CineStill` in `Curves/cinestill-800t/stock.json:3` and re-bake,
   if the names survive REL-12.
4. Proofread the ~110 user-facing strings once, end to end, on device — they have
   never been read in situ at every Dynamic Type size.

**Acceptance criteria.** No user-facing string says `Stock` where `CONTEXT.md`
mandates `Film Stock`; one spelling variant is used consistently in the UI and
matches the App Store Connect primary language; brand names match the rights
holders' own styling.

**How to verify.** `grep -rn '"Stock"' FilmApp/` returns nothing outside comments;
read every screen on device.

---

## H. Robustness and the edge cases a reviewer hits in five minutes

### REL-28 — Untagged photos are rejected outright, with a developer-facing message

**Category:** Robustness · **Blocking:** Should-fix · **Owner:** Engineering · **Effort:** S

**Current state.** `Sources/FilmEngine/ImageDecoder.swift:66-70`:

```swift
guard properties?[kCGImagePropertyProfileName] != nil || exif?[kCGImagePropertyExifColorSpace] as? Int == 1 else {
    // ImageIO supplies a default sRGB CGColorSpace even when the file has
    // no tag. The metadata must establish that assignment explicitly.
    throw FilmError.invalid("This photo has no colour profile; assign one before opening it")
}
```

The reasoning is correct and is a genuine engineering virtue — `README.md` states
*"Untagged inputs are rejected instead of assuming sRGB"*, and
`Tests/FilmEngineTests/Fixtures/untagged.png` exists specifically to assert it. But
the **user experience** of that decision is a dead end: the message tells a
photographer to "assign a colour profile", which is not something anyone can do on
iPhone, and the app offers no way forward.

The immediately preceding guard is worse:
`ImageDecoder.swift:60-63` throws the *same class of* message —
`"Photo has no supported input colour profile"` — when
`CGImageSourceCreateImageAtIndex` returns nil, i.e. when the file is **corrupt or
undecodable**. Two different failures, one misleading message.

Two neighbouring limits produce equally blunt dead ends:
`ImageDecoder.swift:118` — `"Photo exceeds the supported texture dimensions"` for
anything over 16 384 px on an edge (reachable with a long iPhone panorama), and
`Sources/FilmEngine/RenderTypes.swift:20` —
`"Invalid image dimensions or non-finite pixels"`.

Images that reach the picker untagged in practice: anything re-encoded by a
messaging app, many web downloads, some scanner and screenshot-tool output, and
images round-tripped through tools that strip ICC.

**Why it matters.** *(recalled)* Guideline 2.1 — an app must handle its own inputs.
A reviewer's device will contain a mixture of photos, and the first one they pick
that came from a chat app produces an error a normal person cannot act on. It reads
as broken rather than as principled.

**What to do.**

1. Separate the two failures at `ImageDecoder.swift:60-63` and `:66-70` into distinct
   errors, and rewrite both in user language.
2. Offer a way forward rather than a wall. Options, in order of preference:
   - Show a sheet: *"This photo has no colour profile. Dye can open it as sRGB, but
     colours may not be exactly right."* with an **Open as sRGB** button. The
     decoder keeps its strictness; the *app* takes responsibility for the
     assumption, which is the right place for it.
   - Or downsample oversized images rather than refusing them — the Preview path
     already downsamples (`ImageDecoder.swift:74-77`), so this is only a question of
     what the **Export** path does.
3. Route these through REL-31's error-copy work.

**Acceptance criteria.** Opening an untagged PNG, a truncated JPEG and a 20 000 px
panorama each produce a distinct, plain-English message, and at least the untagged
case offers a way to proceed.

**How to verify.** Build a test set — `Tests/FilmEngineTests/Fixtures/untagged.png`
is already one — put them in the simulator's photo library, and open each.

**Cross-reference.** The companion `docs/audits/security.md` reports three further
defects on this same decode path — **SEC-01** (dimensions are bounded but the pixel
count is not), **SEC-02** (no finiteness invariant between decode and `ImageWriter`)
and **SEC-04** (RAW extent converted to `Int` without a range check). They were found
as security issues but they are reached by the ordinary act of opening a photo, so
fix them together with this one. See REL-11.

---

### REL-29 — Export peak memory is unbounded and has never been measured on device

**Category:** Robustness · **Blocking:** Blocker · **Owner:** Engineering · **Effort:** M

**Current state.** An Export of a 48 MP frame (8064 × 6048) as 16-bit TIFF allocates,
concurrently:

| Allocation | Size | Citation |
| --- | ---: | --- |
| Full-resolution source `MTLTexture`, `rgba16Float` | ≈ 390 MB | `Sources/FilmEngine/Export/Export.swift:16`, `Sources/FilmEngine/ImageDecoder.swift:120-124` |
| `ImageWriter.pixels` assembled frame, 16-bit RGBA | ≈ 390 MB | `Sources/FilmEngine/Export/ImageWriter.swift:33`; the header comment at `:14-16` cites 183 MB for the *8-bit* case |
| Encoded output `Data` from `CGImageDestinationFinalize` | ≈ 390 MB uncompressed TIFF | `ImageWriter.swift:88-89`, returned to `Export.swift:22` |
| Tile textures, input + scratch | ≤ 335 MB budget | `Sources/FilmEngine/Export/ExportTypes.swift:72` (`textureBudgetBytes: Int = 320 << 20`), `Export.swift:73-74` |
| The original encoded photo, held for the life of the editor | 5–80 MB | `FilmApp/EditorModel.swift:35`, `:172` |
| Preview textures, thumbnails for 17 Profiles, Preset thumbnails | — | `FilmApp/EditorModel.swift:18`, `:208` |

That is on the order of **1.5 GB peak**, and the app never asks the device how much
it has: `os_proc_available_memory` is not called anywhere, and
`FilmApp/EditorModel.swift:328` constructs `ExportOptions(creationDate: creationDate)`
with **every other option left at its default** — the same 335 MB tile budget on an
iPhone XR as on an iPhone 17 Pro Max. The deployment target is iOS 17
(`FilmApp.xcodeproj/project.pbxproj:247`), which includes 3–4 GB devices whose
foreground jetsam limit is well under this.

The project knows this is unverified. `README.md`: *"Real camera fixtures and
on-device memory and performance validation are still needed: **a simulator does not
reproduce the memory pressure tiling exists for**."*
`docs/performance-audit.md:56-62` confirms all verification was done on the
**iPhone 17 Pro simulator**, that gesture responsiveness is not claimed as verified,
and that *"full-quality preview rendering is not proven to meet a 16.7 ms frame
budget"*.

There is also no memory-pressure handling: no `didReceiveMemoryWarning` equivalent,
no cache eviction of `thumbnails` / `presetThumbnails` under pressure.

**Why it matters.** *(recalled)* Guideline 2.1 — a jetsam kill during Export is a
crash from the reviewer's point of view, and Export is the app's terminal action, so
it is exactly what a reviewer will do last. This is the most likely *runtime* failure
in the app, as REL-06 is the most likely *launch* failure.

**What to do.**

1. Size the tile budget from the device:
   `ExportOptions.textureBudgetBytes = min(320 << 20, os_proc_available_memory() / 4)`
   or similar, passed from `FilmApp/EditorModel.swift:328`.
2. Stop holding the full frame *and* the encoded copy simultaneously. Either stream
   tiles into `CGImageDestination` incrementally, or release `ImageWriter.pixels`
   before the encoded `Data` is handed back, or write the encoded bytes straight to
   the destination URL instead of returning `Data` to the caller
   (`Export.swift:22` → `FilmApp/EditorModel.swift:327-330`).
3. Cap or warn on 16-bit TIFF at very large frame sizes, or drop TIFF from the
   shipping build. It is the format that doubles every buffer and the one fewest
   users need.
4. Evict `thumbnails` and `presetThumbnails` before starting an Export.
5. **Measure on the oldest supported device.** Instruments Allocations + a
   `MetricKit` `MXAppExitDiagnostic` check, on an A12-class iPhone, with a 48 MP
   input in each of HEIF / JPEG / TIFF.

**Acceptance criteria.** A 48 MP Export in every format completes on the oldest
device the app claims to support, with peak footprint recorded and a margin below
that device's jetsam limit. No `MXAppExitDiagnostic` memory-resource-exception in a
TestFlight run.

**How to verify.** Instruments → Allocations, high-water mark, on device; repeat for
all three formats; confirm the Photos asset is written.

**Cross-reference.** The companion `docs/audits/performance.md` reaches the same
conclusion independently as **PERF-02** (*"Full-resolution decode holds ~1.45 GB of
buffers at once"*), and its **PERF-01** reports that the tile plan degenerates into
44× overdraw above roughly a 4 500 px frame — which makes the Export both slower and
larger than the estimate above. Use PERF-02's figure in place of the estimate here.
See REL-11.

---

### REL-30 — Exported files accumulate in the temporary directory forever

**Category:** Robustness · **Blocking:** Should-fix · **Owner:** Engineering · **Effort:** S

**Current state.** `FilmApp/EditorModel.swift:416-432` writes every Export to a
**fresh UUID-named subdirectory** of `FileManager.default.temporaryDirectory`:

```swift
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let url = directory.appendingPathComponent(name)
try data.write(to: url, options: .atomic)
```

Cleanup happens on **cancellation only** (`:425-430`) and on a Photos-save failure
(`:341`). On the **success** path — `:345-348`, `export = .finished(...)` — the file
is deliberately kept alive so `ShareLink(item: record.url)`
(`FilmApp/ExportSheet.swift:229`) can share it, and is then **never deleted**. There
is no sweep at launch, no sweep on dismissing the sheet
(`FilmApp/EditorModel.swift:387-390`), and no age-based eviction.

Each successful Export therefore leaves a 5–400 MB file behind. Ten exports of a
48 MP TIFF is several gigabytes of the user's storage in `tmp/`.

**Why it matters.** *(recalled)* iOS may purge `tmp/` when the device is under
storage pressure, but only when the app is not running and only opportunistically —
it is not a substitute for cleaning up. A photo app that silently consumes several
gigabytes is a support burden and a one-star review; Guideline 2.5.1's "use APIs as
intended" is the closest rule, and *(recalled)* Apple's data-storage guidance is
explicit that `tmp/` contents should be deleted when no longer needed. It also
compounds REL-29 and REL-33's low-storage case: a full disk makes the *next*
`data.write(to:)` throw.

**What to do.**

1. Sweep `temporaryDirectory` on launch (and on `dismissExport()`,
   `FilmApp/EditorModel.swift:387-390`), deleting export directories older than a
   short window.
2. Delete the previous Export's directory when a new one starts
   (`exportImage()`, `:299`).
3. Better: write into a single, known subdirectory (`tmp/Exports/`) so the sweep is
   unambiguous and cannot touch anything else.
4. Keep the current file alive only while the finished sheet is on screen.

**Acceptance criteria.** After ten Exports and a relaunch, `tmp/` holds at most one
export file. Storage usage in Settings → General → iPhone Storage → Dye does not
grow without bound.

**How to verify.** On device, export ten times, check Settings → iPhone Storage; or
in the simulator, `du -sh` the app container's `tmp/`.

**Cross-reference.** The companion `docs/audits/security.md` reaches the same
conclusion independently as **SEC-03**, and frames it as a **privacy** defect — a
full-resolution copy of the user's photograph left on disk indefinitely — rather than
as a storage one. That framing is stronger and is the one to use, including when
answering REL-08. See REL-11.

---

### REL-31 — Raw engine error strings are shown to users verbatim

**Category:** Robustness / Copy · **Blocking:** Should-fix · **Owner:** Engineering · **Effort:** M

**Current state.** `Sources/FilmEngine/RenderTypes.swift:4-9` makes `FilmError`
`LocalizedError` with `errorDescription` returning the raw message, and the app then
puts `error.localizedDescription` straight on screen in **eight** places:
`FilmApp/EditorModel.swift:142`, `:185`, `:342`, `:352`, `:375`, `:546`, `:568`;
`FilmApp/PresetSheet.swift:86`, `:137`, `:142`; `FilmApp/Editor/OutputStageCards.swift:55`;
`FilmApp/ContactSheetView.swift:76`. It is rendered at
`FilmApp/Editor/EditorView.swift:141` (the deck error strip) and
`:198` (the welcome screen).

The engine's messages are written for engineers. A user can currently be shown:

- `"Profile portra-400: mid-grey density is not above base density; the scan cannot auto-balance"` (`Sources/FilmEngine/Renderer.swift:489`)
- `"Cannot encode filmResponse"` (`Renderer.swift:208`)
- `"Missing shader grainDyeCloud"` (`Renderer.swift:54`)
- `"Profile has no Film Response payload"` (`Renderer.swift:946`)
- `"Density Curve must contain 1024 entries"` (`Renderer.swift:956`)
- `"The Working Space is not a deliverable; export Display P3 or sRGB"` (`Sources/FilmEngine/Export/ImageWriter.swift:28`)
- `"Exported LUT size must be 2...65"` (`Sources/FilmEngine/Export/ExportedLUT.swift:25`)
- `"Metal is unavailable"` (`Renderer.swift:37`)
- `"Duplicate Profile identity in Catalogue"` (`Sources/FilmEngine/Profiles/ProfileCatalogue.swift:9`)

Most of these are unreachable in a correct build — but "unreachable in a correct
build" is exactly the assumption REL-06 says has never been tested.

**Why it matters.** *(recalled)* Guideline 4.0 / 2.3 — user-facing text should be
comprehensible. `"Cannot encode filmResponse"` on a reviewer's screen reads as a
half-finished app. There is also a mild information-disclosure angle: the errors
expose internal Profile ids, payload names and shader names.

**What to do.**

1. Keep `FilmError` as-is — it is the right internal vocabulary and the tests depend
   on it. Add a **presentation layer** in the app: map `FilmError` cases to user
   copy, with a small set of user-meaningful outcomes ("This photo could not be
   opened", "This film stock could not be loaded", "The export could not be
   completed") and a "Details" disclosure for the engine string.
2. Distinguish *recoverable* from *fatal*: a Profile that will not load should
   remove that Stock from the browser rather than leaving an error strip up.
3. Add recovery affordances — a Retry on render failure, an Open Settings on the
   permission case (REL-10).
4. Two messages are already good and should be the model:
   `FilmApp/EditorModel.swift:325` and `:436`.

**Acceptance criteria.** No engine identifier (Profile id, payload name, shader name,
`Working Space`, `Density Curve`) appears in a message a user can see; every error
state offers either a recovery action or a clear explanation.

**How to verify.** Force each failure with a modified Catalogue in a debug build and
screenshot every resulting message.

---

### REL-32 — The SwiftData container has no failure handling and no migration plan

**Category:** Robustness · **Blocking:** Blocker · **Owner:** Engineering · **Effort:** M

**Current state.** `FilmApp/FilmApp.swift:5-8` is the entire app entry point:

```swift
@main
struct FilmApp: App {
    var body: some Scene { WindowGroup { EditorView() }.modelContainer(for: Preset.self) }
}
```

`FilmApp/PresetSheet.swift:5-17` defines the model:

```swift
@Model final class Preset {
    var name: String
    var stockID: String
    var settingsData: Data
    var createdAt: Date
```

Two problems.

1. **No failure handling on launch.** *(recalled)* SwiftUI's
   `.modelContainer(for:)` traps — it calls `fatalError` — if the container cannot be
   created, which happens on a corrupt store or a failed migration. There is no
   `do/catch`, no in-memory fallback, no "reset your presets" recovery. A single
   corrupt store file is an unrecoverable launch crash for that user, with no path
   back except deleting the app.
2. **No schema versioning.** There is no `VersionedSchema`, no `SchemaMigrationPlan`,
   and no `@Attribute(.unique)` or identifier on `Preset`. The moment `Preset` gains
   or renames a property after v1 ships, SwiftData must migrate; a lightweight
   migration may succeed silently, but anything more will fail — and per (1) that
   failure is a launch crash for every user with saved **Presets**.

Mitigating factors, to be fair: the payload is versioned *inside* `settingsData` by
`RenderSettings`' own `Codable` conformance, and the app already degrades gracefully
when decoding fails (`FilmApp/PresetSheet.swift:158`, `:169` —
*"Saved before this version; cannot be read"*) or when a Stock has left the Catalogue
(`FilmApp/EditorModel.swift:436-441`, `PresetSheet.swift:175`). That thinking is
exactly right and just needs extending one level up, to the store itself.

**Why it matters.** *(recalled)* Guideline 2.1 — crash on launch. It will not bite at
submission (an empty store always opens); it will bite on the **first update after
launch**, when every user who saved a Preset runs a migration nobody planned. That is
worse than a rejection, because by then the app is live.

**What to do.**

1. Create the `ModelContainer` explicitly with `try`. On failure, fall back to an
   in-memory container so the app **launches**, and surface a non-fatal notice
   offering to reset saved Presets.
2. Define `VersionedSchema` for `Preset` v1 now, and a `SchemaMigrationPlan` stub, so
   v2 has somewhere to go.
3. Add a `schemaVersion` field to what `settingsData` encodes, if `RenderSettings`
   does not already carry one.
4. Test the upgrade path: install a build with saved Presets, install the next build
   over it, confirm the Presets survive.

**Acceptance criteria.** The app launches with a deliberately corrupted store file;
a v1 → v2 schema change preserves saved Presets or fails without crashing.

**How to verify.** Corrupt the store in the simulator container and launch. Then
build a v2 with a changed `Preset` schema and install over a v1 with saved Presets.

---

### REL-33 — Reviewer edge-case matrix

**Category:** Robustness · **Blocking:** Should-fix · **Owner:** Engineering · **Effort:** M

**Current state.** Assessed by reading; **none of it has been run**, on device or in a
simulator, by this audit.

| Scenario | Assessment | Citation |
| --- | --- | --- |
| **First launch, no photo** | Good. A real empty state — icon, heading, explanation, a prominent picker button, and an accessibility hint. | `FilmApp/Editor/EditorView.swift:157-213` |
| **Cancelling the picker** | Safe. `PhotosPicker` leaves the `photo` binding unchanged, and the `.task(id: photo)` guard returns early. | `EditorView.swift:28-32` |
| **Photo-library read permission denied** | Not applicable, and this is a genuine strength: input goes through out-of-process `PhotosPicker`, so **no read permission is ever requested**. `README.md` says so too. | `EditorView.swift:184`, `EditorModel.swift:145` |
| **Photos add permission denied** | Bad. Kills the whole Export with no share fallback. | REL-10 |
| **No photos on the device** | The system picker shows its own empty state. Fine. | — |
| **Corrupt / undecodable image** | Wrong message. | REL-28 |
| **Untagged image** | Dead end. | REL-28 |
| **Enormous image (> 16 384 px)** | Hard refusal. Reachable with a long iPhone panorama. | `ImageDecoder.swift:118` |
| **Unsupported format** | `"Unsupported photo file"` — acceptable, but see REL-31. | `ImageDecoder.swift:25` |
| **iCloud photo not downloaded, no network** | **Untested and concerning.** `item.loadTransferable(type: Data.self)` (`EditorModel.swift:153`) triggers an iCloud download with **no timeout, no progress and no cancel**. The UI shows an indefinite `ProgressView("Loading photo…")` (`EditorView.swift:181`). Offline or on a slow connection this hangs with no way out but force-quit. | `EditorModel.swift:153`, `EditorView.swift:181` |
| **No network generally** | Otherwise fine — the app makes no network calls at all (REL-08). | — |
| **Backgrounding mid-Export** | **Untested.** No `beginBackgroundTask`, no `BGProcessingTask`. A 48 MP Export can exceed the ~30 s of background execution iOS grants, after which the app suspends mid-render. It should resume, but this has never been observed, and the Photos write and the temp write are the risky moments. | `EditorModel.swift:319-355` |
| **Low storage during Export** | Partially handled: `data.write(to:)` throws and lands in `.failed`. But the encode has already consumed ~400 MB of RAM by then (REL-29), and REL-30's accumulated temp files are a likely *cause* of the low storage. | `EditorModel.swift:422`, `:351-353` |
| **Low-memory termination** | Unhandled. | REL-29 |
| **Thermal throttling** | **Well handled** — a real strength. State is watched live (`EditorModel.swift:292-295`, `:582-596`), the Export inserts a 50 ms gap per Tile when throttling (`Sources/FilmEngine/Export/Export.swift:93`), and the UI explains it rather than hiding it (`FilmApp/ExportSheet.swift:160-188`). | — |
| **Cancelling an Export** | Handled per Tile, with the partial file deleted. | `Export.swift:78`, `EditorModel.swift:381-385`, `:425-430` |
| **Dismissing the Export sheet mid-render** | Handled — the sheet is `interactiveDismissDisabled` while exporting and the work continues. | `ExportSheet.swift:49` |
| **Rotation** | Two layouts exist but neither is verified, and orientations are undeclared. | REL-04 |
| **iPad / Split View** | Unverified. | REL-05 |
| **Dark Mode** | Forced. | REL-24 |
| **Older / low-end devices** | Never run on one. Deployment target is iOS 17, so A12-class devices are in scope; every measurement in `docs/performance-audit.md` is from a simulator on Apple Silicon. Metal shaders are compiled **from source at runtime** (`Renderer.swift:47-49`, 22 compute pipelines from `makeLibrary(source:)`), which on a cold first launch with no driver shader cache is measurably slow — `docs/performance-audit.md:41` puts renderer setup at 37–42 ms on a Mac; on an A12 it will be considerably more. | `Renderer.swift:44-58` |
| **Preview render budget** | `docs/performance-audit.md:45-47`: *"full-quality preview rendering is not proven to meet a 16.7 ms frame budget, much less an 8.3 ms budget."* Every dial drag re-renders. | — |

**Why it matters.** *(recalled)* Guideline 2.1. Reviewers are efficient: they open
the app, deny the first permission they are offered, pick an awkward photo, rotate
the device, and export. Three of those five are currently weak.

**What to do.**

1. Add a timeout and a Cancel to the photo-open path
   (`FilmApp/EditorModel.swift:145-186`) and show real progress for an iCloud
   download.
2. Wrap the Export in `UIApplication.beginBackgroundTask` so a backgrounded Export
   gets its full grace period, and handle expiry by cancelling cleanly.
3. Precompile the Metal library into a `.metallib` at build time instead of
   `makeLibrary(source:)` at runtime — this removes the largest cold-start cost and
   also stops shipping the shader source in the bundle.
4. Run the whole matrix on the oldest supported device before submitting, and record
   the results here.

**Acceptance criteria.** Every row above is marked "verified on device" with a date,
or is explicitly accepted as a known limitation.

**How to verify.** Work the table row by row on an A12-class device and a current
device, in Airplane Mode and online.

---

## I. Release engineering

### REL-34 — CI never builds Release, never archives, never signs

**Category:** Release engineering · **Blocking:** Should-fix · **Owner:** Engineering · **Effort:** M

**Current state.** Two workflows exist. `.github/workflows/profile-candidates.yml` is
a label-triggered Catalogue review job and is not release-relevant.
`.github/workflows/ci.yml` has three jobs:

- `changes` — `Scripts/ci_scope.py` classifies the diff; `FilmApp/` and
  `FilmApp.xcodeproj/` set `app=true`, `Tests/` and `ProfileBaker/` set
  `engine=true`, anything else sets both, and `README.md` / `CONTEXT.md` / `docs/`
  set neither (`Scripts/ci_scope.py:7-23`).
- `engine_tests` — `swift build`, the full Swift Testing suite, an isolated
  performance-budget test, a Catalogue re-bake verified with
  `git diff --exit-code -- Sources/FilmEngine/Catalogue`, and per-Stock numerical
  **Step Wedges**. This job is genuinely strong.
- `app` — **one** command:
  `xcodebuild -project FilmApp.xcodeproj -scheme FilmApp -sdk iphonesimulator -configuration Debug -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO build`,
  under `DEVELOPER_DIR=/Applications/Xcode_26.3.app` (needed for the iOS 26 Liquid
  Glass SDK, `FilmApp/Design/Surfaces.swift:538-540`), plus
  `python3 Scripts/check-dial-mapping.py`.

So the release-relevant coverage is: **Debug, simulator, unsigned, no archive, no
export, no device, no UI tests, no snapshot tests, no launch test.** No shared
`.xcscheme` is committed (`find FilmApp.xcodeproj -type f` → only `project.pbxproj`),
so the scheme `xcodebuild` uses is auto-generated and its Archive action's
configuration is not under version control.

**Why it matters.** Everything REL-06 lists — signing, entitlements, provisioning,
`-O` codegen, SPM resource-bundle layout inside a signed `.ipa` — is untested, and
will be tested for the first time by the person doing the submission, under time
pressure.

**What to do.**

1. Commit `FilmApp.xcodeproj/xcshareddata/xcschemes/FilmApp.xcscheme` with Archive
   pinned to Release.
2. Add a `release` job (on `main` and on tags) that runs
   `xcodebuild -configuration Release -destination 'generic/platform=iOS' archive`
   with `CODE_SIGNING_ALLOWED=NO` — that alone catches `-O` build failures and
   Release-only warnings without needing secrets.
3. Add a signed archive + `-exportArchive` + TestFlight upload job gated on a tag,
   using an App Store Connect API key in GitHub secrets and
   `xcrun altool` / `xcrun notarytool` as appropriate.
4. Add a smoke test that boots a simulator, launches the app and asserts it reaches
   the welcome screen — the cheapest possible guard against REL-06's force-unwrap
   traps. `Tests/FilmEngineTests/` has no UI target; a minimal XCUITest target is
   the right shape.
5. Add the `accessibility5` snapshot check from REL-25.

**Acceptance criteria.** A push to `main` produces a green Release archive build; a
tag produces a TestFlight build without anyone running `xcodebuild` by hand.

**How to verify.** Push a branch that breaks only under `-O` and confirm CI catches
it; cut a tag and watch the build appear in TestFlight.

---

### REL-35 — No crash reporting and no dSYM plan

**Category:** Release engineering · **Blocking:** Should-fix · **Owner:** Engineering · **Effort:** S

**Current state.** No crash-reporting SDK of any kind — no Crashlytics, Sentry,
Bugsnag, or anything else (verified in REL-07/REL-08: zero third-party dependencies).
No `MetricKit` / `MXMetricManager` use anywhere. No `Logger` or `OSLog` instance —
`import os` at `FilmApp/EditorModel.swift:5` is used only for `OSAllocatedUnfairLock`
(`:309`). `DEBUG_INFORMATION_FORMAT` is not set in `project.pbxproj`, so it takes the
Xcode default (`dwarf-with-dsym` for Release), and there is no dSYM archiving step in
CI (REL-34).

**Why it matters.** *(recalled)* No SDK is required — Xcode Organizer's Crashes
organizer symbolicates App Store and TestFlight crashes automatically **provided the
dSYM is uploaded with the build and the user has opted into sharing diagnostics**.
That is a workable baseline for v1 and keeps REL-08's "Data Not Collected" answer
intact, which a third-party crash SDK would not. But given REL-06, REL-29 and REL-32
all describe plausible crashes that have never been reproduced, you want *some*
visibility.

**What to do.**

1. Confirm `DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"` for Release explicitly
   rather than relying on the default, and confirm "Upload symbols" is on at
   submission.
2. Archive the `.xcarchive`'s `dSYMs/` as a CI artefact keyed by
   `CURRENT_PROJECT_VERSION` (REL-02), so a crash from any build can be symbolicated
   later.
3. Add `MetricKit`: subscribe to `MXMetricPayload` and `MXDiagnosticPayload` and log
   `MXCrashDiagnostic` / `MXAppExitDiagnostic` locally. It is a first-party API, adds
   no dependency, sends nothing anywhere, and directly answers REL-29 (memory
   resource exceptions) and REL-33 (background-task expiry).
4. If you later add a third-party crash reporter, revisit REL-07 and REL-08 —
   it changes the privacy manifest and the nutrition labels.

**Acceptance criteria.** Every uploaded build has its dSYM retained; Organizer shows
symbolicated frames for a deliberately triggered TestFlight crash.

**How to verify.** Ship a TestFlight build with a debug-only crash trigger, crash it,
and read the frames in Organizer.

---

### REL-36 — No versioning scheme, no tags, no release checklist

**Category:** Release engineering · **Blocking:** Should-fix · **Owner:** Engineering · **Effort:** S

**Current state.** `git tag` → **zero tags**. No `CHANGELOG.md`. No release
documentation of any kind — `docs/` holds engine design documents and audits, and
`docs/agents/issue-tracker.md` points at a Linear project
(`https://linear.app/memoji-inc/project/dye-08b875851eb4/issues`) as the requirements
home. No `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` to increment (REL-02).
`README.md` documents `swift build`, `swift test` and one `xcodebuild` line — nothing
about producing a release.

**Why it matters.** Not a guideline issue. It matters because a first submission has
roughly forty discrete steps, most of them one-shot, several of them irreversible
(a bundle identifier cannot be changed once a build is uploaded; an app name is
reserved), and there is currently nothing written down.

**What to do.**

1. Adopt and record the scheme: `MARKETING_VERSION` is semantic and user-visible;
   `CURRENT_PROJECT_VERSION` is a monotonic integer, ideally CI-driven.
2. Tag every submitted build `v<MARKETING_VERSION>+<CURRENT_PROJECT_VERSION>`.
3. Add `CHANGELOG.md`, which doubles as the source for App Store "What's New".
4. Add `docs/release.md` — or promote the Pre-submission checklist at the end of this
   audit into one — covering the repeatable part of the process.

**Acceptance criteria.** Every App Store build corresponds to a git tag; the release
process is documented well enough for someone who is not Guillermo to follow it.

**How to verify.** `git tag` lists the shipped versions; a dry run of the checklist.

---

### REL-37 — Signing, provisioning, TestFlight and App Store Connect setup

**Category:** Release engineering · **Blocking:** Blocker · **Owner:** Owner / App Store Connect · **Effort:** M

**Current state — mostly unverifiable from here.** What the repo shows:

- `FilmApp.xcodeproj/project.pbxproj:241-242`, `:263-264` —
  `CODE_SIGN_STYLE = Automatic;` and `DEVELOPMENT_TEAM = X76BWPRADX;`, hard-coded in
  **both** configurations.
- `PRODUCT_BUNDLE_IDENTIFIER = app.memoji.dye` (`:248`, `:270`).
- No `CODE_SIGN_ENTITLEMENTS` and **no `.entitlements` file anywhere** — which is
  correct: the app uses no capability that requires one (no push, no iCloud, no App
  Groups, no Sign in with Apple, no HealthKit, no associated domains). Photos
  add-only needs a usage-description string, not an entitlement.
- CI never signs (`CODE_SIGNING_ALLOWED=NO`), so signing has never been exercised
  (REL-06, REL-34).
- `README.md` says only *"For a device, select your signing team in Xcode."*

**What cannot be checked from here** and must be confirmed by the owner:

1. Is the Apple Developer Program membership (team `X76BWPRADX`, "Memoji Inc")
   active and paid?
2. Is it an **Organization** account? If so, is the D-U-N-S number verified and is
   the legal entity name what should appear as the seller?
3. Do the Paid Applications / Free Applications agreements need accepting? (Free
   apps still need the free agreement accepted before a listing can be submitted
   *(recalled)*.)
4. Does an App Store Connect record exist for `app.memoji.dye`? Is the App ID
   registered on the developer portal?
5. Is a Distribution certificate present, and is an App Store provisioning profile
   available (Xcode-managed is fine)?
6. Is TestFlight internal testing set up, and are there testers?
7. Is `X76BWPRADX` the right team to ship under, or is it a personal team?

**Why it matters.** *(recalled)* Every one of these is a hard gate. Hard-coding
`DEVELOPMENT_TEAM` in the project also means anyone else who clones the repo cannot
build to a device without editing it — a small thing, but it belongs in an
`.xcconfig` or a local override rather than in the committed project.

**What to do.**

1. Answer 1–7 above and record the answers.
2. Reserve the app name in App Store Connect early — see REL-40; names are
   first-come.
3. Create the App Store Connect record and push one signed build to TestFlight
   **before** any of the listing work, because the upload is where REL-01, REL-02 and
   REL-40 actually fail.
4. Move `DEVELOPMENT_TEAM` into an `.xcconfig` that can be overridden locally.

**Acceptance criteria.** A signed build appears in TestFlight and installs on a
device via the TestFlight app.

**How to verify.** Do it. TestFlight is the only real proof.

---

## J. Store listing assets

### REL-38 — No store screenshots exist at any required size

**Category:** Listing · **Blocking:** Blocker · **Owner:** Design · **Effort:** M

**Current state.** There is no store-asset directory of any kind — no
`fastlane/screenshots`, no `store/`, no marketing folder. The only screenshots in the
repo are PR evidence, and all six are unusable:

| File | Size | Problem |
| --- | --- | --- |
| `docs/pr-evidence/identity-rail/01-editor.png` | 1206 × 2622 | Wrong size (6.3"); stale; Apple sample photo |
| `docs/pr-evidence/identity-rail/02-stock-browser.png` | 1206 × 2622 | Shows the **pre-`cde0c7f` UI** — `"Stock"` headline and `"Identity"` where `HEAD` shows `"Film Stock"` and `"No Film Stock"` |
| `docs/pr-evidence/identity-rail/03-output-browser.png` | 1206 × 2622 | as above |
| `docs/pr-evidence/ios-glass-toolbar/01-welcome.png` | 1206 × 2622 | Wrong size; Apple sample photo |
| `docs/pr-evidence/ios-glass-toolbar/02-editor.png` | 1206 × 2622 | as above |
| `docs/pr-evidence/ios-glass-toolbar/03-largest-text.png` | 1206 × 2622 | as above (useful as REL-25 evidence, not as a store asset) |

Three separate disqualifiers: **wrong dimensions** (1206 × 2622 is the 6.3" iPhone;
App Store Connect's required iPhone set is the 6.9" class, 1290 × 2796 or 1320 × 2868
*(recalled — re-verify the current required sizes, Apple changes them most years)*);
**stale UI**; and **Apple's own simulator sample photograph** (REL-17).

**Why it matters.** *(recalled)* Screenshots are a mandatory submission field —
at minimum one 6.9" iPhone set, plus a 13" iPad set if `TARGETED_DEVICE_FAMILY`
includes iPad (REL-05). Guideline 2.3.3 requires screenshots to show the app in
actual use and to accurately reflect it; a screenshot of a UI that no longer exists
is a 2.3 problem, and Apple explicitly disallows screenshots that are not of the app.

**What to do.**

1. **Resolve REL-12 first.** Every screenshot will show Display Names; regenerating
   them before the trademark decision is wasted work.
2. Source photographs you own, or explicitly licensed stock with the licence recorded
   (REL-17). Pick images that actually demonstrate the engine: skin tones for Portra,
   a bright practical light for CineStill halation, a high-contrast scene for Tri-X,
   a saturated landscape for Velvia.
3. Capture on a 6.9" device or simulator. A sensible five: the welcome screen; the
   editor with a graded frame; the **Film Stock** browser; the **Contact Sheet**; the
   Export sheet or a before/after.
4. Add iPad captures only if REL-05 keeps iPad.
5. Consider an app preview video — optional, and the Contact Sheet and the dial
   interaction both film well *(recalled: ≤ 30 s, captured from the device, no
   non-app footage)*.
6. Store the final assets in the repo (`store/screenshots/`) with a README recording
   device, OS, build and image rights, and delete or replace the stale PR evidence.

**Acceptance criteria.** A complete 6.9" iPhone set (and a 13" iPad set if
applicable) exists, matches `HEAD`'s UI, uses rights-cleared imagery, and is
consistent with the REL-12 decision.

**How to verify.** Upload to App Store Connect and confirm no size warnings; compare
each screenshot side by side with the running app.

---

### REL-39 — No support URL

**Category:** Listing · **Blocking:** Blocker · **Owner:** Owner · **Effort:** S

**Current state.** No support URL, no contact address, no feedback affordance
anywhere. Grepping for `support`, `contact`, `feedback` and `mailto:` finds nothing
user-facing. `FilmApp/SettingsView.swift` offers only a Glossary. The repository's
only external link is the Linear project in `docs/agents/issue-tracker.md:3`, which
is internal.

**Why it matters.** *(recalled)* The support URL is a mandatory App Store Connect
field; the listing cannot be submitted without one, and Apple checks that it
resolves and is relevant. Guideline 1.5 also expects developers to provide a means
of contact and to respond.

**What to do.**

1. Publish a support page at a stable URL on the same domain as the privacy policy
   (REL-09) — a short page describing the app, an email address, an FAQ covering the
   things this audit predicts people will hit (untagged photos, REL-28; Photos
   permission, REL-10; export storage, REL-30), and the REL-14 disclaimer.
2. Enter it in App Store Connect. Set the marketing URL too if you have one.
3. Add a Settings row linking to it, beside the privacy policy and acknowledgements
   rows (`FilmApp/SettingsView.swift:10-16`).
4. Make sure the mailbox is actually monitored.

**Acceptance criteria.** The support URL resolves, names a contact method, and is
entered in App Store Connect.

**How to verify.** Load it; send a test message and confirm it arrives.

---

### REL-40 — Age rating, category, export compliance, description, keywords, pricing

**Category:** Listing · **Blocking:** Blocker · **Owner:** Owner / App Store Connect · **Effort:** M

**Current state.** None of this exists in the repo, and most of it lives only in App
Store Connect, so it is **unverifiable from here**. What the repo determines:

**Export compliance / encryption.** `ITSAppUsesNonExemptEncryption` is **absent**
from `project.pbxproj` (verified, 0 hits). The app contains no cryptography: no
CryptoKit in shipping code (`CryptoKit` appears only in the non-shipping Baker and
tests), no `SecItem`/keychain, no TLS because there is no networking at all (REL-08).
`Sources/FilmEngine/Profiles/ProfileContainer.swift` hashes for a source fingerprint
but that is not encryption. So the answer is **No**.

*(recalled)* Without the key in the plist, App Store Connect prompts for an export
compliance answer on **every single upload** — a small but permanent friction, and a
common cause of a build sitting in "Missing Compliance" and never reaching testers.
Set it once (REL-04).

**Age rating.** Nothing in the app suggests anything above the lowest tier: no
user-generated content sharing, no web view, no chat, no location, no ads, no
in-app browser, no purchases (REL-22), no violence, no gambling. The only
user-controlled content is the user's own photograph, which never leaves the device.
Expect **4+**, but answer the questionnaire honestly — *(recalled)* Apple replaced the
old questionnaire with a more granular one and the exact questions change.

**Category.** Primary: **Photo & Video**. A secondary category is optional;
Graphics & Design is arguable but Photo & Video is clearly right.

**Everything else that must be authored.** Description (up to 4000 characters),
promotional text (170, editable without a new build — useful), subtitle (30),
keywords (100), what's new, copyright line, marketing URL (optional), primary
language, price tier (REL-22), availability, and the App Privacy questionnaire
(REL-08).

**Why it matters.** *(recalled)* Every field above is a hard gate on "Submit for
Review". Guideline 2.3 governs all of it, and 2.3.1 specifically prohibits hidden or
undocumented features — which is relevant here in one narrow way: the **Contact
Sheet** and the **Exported LUT** are genuinely unusual features and should be
described, not left for a reviewer to stumble into.

**What to do.**

1. Set `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` (REL-04) and confirm the
   answer is correct at submission — if a crash reporter (REL-35) or any networking
   is ever added, re-answer.
2. Reserve the app name in App Store Connect now; "Dye" is a common word and may
   already be taken. Have fallbacks ready.
3. Write the description against REL-19's constraint — "physically motivated models
   of analog film stocks", never "accurate". `README.md:3` and `CONTEXT.md:3` already
   contain the right sentence.
4. Choose keywords with no third-party marks (REL-13).
5. Complete the age-rating questionnaire and the App Privacy questionnaire (REL-08).
6. Note the review-notes field: tell the reviewer they need photos in the library,
   that Export writes to Photos and needs the add permission, and — if REL-12
   resolves to keeping brand names — state the nominative-use position and the
   disclaimer up front. A reviewer who reads that first is much less likely to open
   a 5.2 rejection.

**Acceptance criteria.** Every App Store Connect field is populated; the description
makes no accuracy claim the accuracy audit does not support; encryption compliance is
answered in the plist so uploads stop prompting.

**How to verify.** Walk the App Store Connect submission form to the point where
"Submit for Review" is enabled, without submitting.

---

## Open questions for the owner

These are the decisions only Guillermo can make. Several of them gate other work, so
they are ordered by how much downstream effort they unblock. Record the answer and
the date against each one, in this file.

**Q1 — Trademark strategy. (Gates REL-12, REL-13, REL-14, REL-17, REL-38, and the
risk weighting of REL-22.)**
Which option: A (rename the Catalogue to non-trademarked names), B (keep the names,
add a disclaimer, strip marks from name/subtitle/keywords), C (seek permission), or
D (rename the Catalogue, describe the inspiration in the store copy only)? This is the
single highest-leverage decision in the audit: it determines twelve Display Names,
five Contrast Filter names, the app name and subtitle, the keyword field, every
screenshot, and whether the app is a takedown target after launch. Nothing in the
store listing should be authored before it is answered.
*Related:* is the public GitHub repository itself part of the exposure you want to
carry (REL-15, REL-16)?

**Q2 — Business model. (Gates REL-22, REL-37, REL-40, and interacts with Q1.)**
Free with no In-App Purchase, paid up-front, or freemium? "Free, no IAP" is by far the
cheapest path to a first submission and keeps the privacy answers trivial. Anything
else adds StoreKit 2, a paywall, restore-purchases, subscription disclosure and
sandbox testing (an **L**), and materially raises the trademark stakes in Q1.

**Q3 — iPad. (Gates REL-05, REL-04, REL-38.)**
Drop it (`TARGETED_DEVICE_FAMILY = "1"`, iPhone-only, no iPad screenshots), or fund a
real iPad layout with Split View and Stage Manager verification plus a 13" screenshot
set? The project currently claims iPad support it has never exercised.

**Q4 — Launch scope. (Gates REL-19, REL-20, REL-29, REL-33.)**
Does v1 ship before the grain defect (REL-20) is fixed and before the Export memory
profile is measured on an A12-class device (REL-29)? My recommendation is no on both:
grain is the reason people use a film emulator, and Export is the terminal action a
reviewer performs. But that is a scope call, not an audit finding.

**Q5 — Which Stocks ship. (Gates REL-23, REL-41, and interacts with Q1 and Q2.)**
Do the five synthetic studies appear in the shipping Catalogue at all, and in what
order does the browser present the twelve named ones? Related: does CineStill 800T
ship at all, given it carries eight Approximations (REL-18), the weakest source
provenance in the repo (REL-15), and 76 MB of largely duplicated payload (REL-41)?
Dropping it would simultaneously reduce the legal, honesty and size exposure.

**Q6 — Accuracy positioning. (Gates REL-19, REL-40.)**
How does the store description describe what the app does? "Physically motivated
models of analog film stocks" is defensible and is already the project's own language;
"accurate emulation" is not supported by `docs/audits/film-stock-accuracy.md`. Also:
should the app *surface* Provenance to the user as a feature, rather than only
labelling Approximations?

**Q7 — Spelling variant. (Gates REL-27, REL-26.)**
British or U.S. English in the user-facing copy? The app is currently British
throughout (`Colour`, `mid-grey`), which reads as foreign in the largest market.
This gets more expensive with every string added.

**Q8 — Appearance lock. (REL-24.)**
Keep the forced dark mode as a deliberate colour-critical decision, or finish the
light palette that `Tokens.swift:107` already starts?

**Q9 — Account and identity. (REL-37.)**
Is the Apple Developer Program membership for team `X76BWPRADX` active and paid? Is it
an Organization account with a verified D-U-N-S? Is `app.memoji.dye` the final bundle
identifier — it cannot be changed after the first upload — and do you own the domain
the privacy policy and support URLs will live on (REL-09, REL-39)?

**Q10 — Who else can ship this. (REL-36.)**
Is the release process required to be reproducible by someone other than you? If yes,
the checklist below needs to become `docs/release.md` and the hard-coded
`DEVELOPMENT_TEAM` needs to move into an `.xcconfig`.

---

## Pre-submission checklist

One flat, ordered list. Work top to bottom: decisions first, because they invalidate
downstream work; then the build artefacts that make an upload possible; then the
runtime fixes; then the listing. Each item names the finding it closes.

**Decisions (do these first — everything else depends on them)**

- [ ] Answer **Q1** and record the trademark strategy with a date · REL-12
- [ ] Answer **Q2** and record the business model · REL-22
- [ ] Answer **Q3** and record the iPad decision · REL-05
- [ ] Answer **Q4** and record the launch scope · REL-20, REL-29
- [ ] Answer **Q5** and record which Stocks ship and in what order · REL-23, REL-41
- [ ] Answer **Q6** and record the accuracy positioning · REL-19
- [ ] Answer **Q7** and record the spelling variant · REL-27
- [ ] Answer **Q8** and record the appearance decision · REL-24
- [ ] Answer **Q9**: confirm the developer account, team, entity and bundle identifier · REL-37
- [ ] Confirm you own the domain for the privacy policy and support URLs · REL-09, REL-39

**Legal**

- [ ] Apply the Q1 decision to the twelve `Curves/*/stock.json` `displayName` fields · REL-12
- [ ] Re-run `Scripts/bake-catalogue.sh` on a Mac and commit the regenerated Catalogue · REL-12
- [ ] Remove or genericise the five `Wratten N` strings at `FilmProfile.swift:43-47` · REL-12
- [ ] Remove `"Kodak's"` from `FilmApp/Editor/Parameter.swift:578` · REL-12
- [ ] Change the `"kodachrome-64"` fixture id at `FilmApp/PresetSheet.swift:285` · REL-12
- [ ] Change the Export filename at `FilmApp/EditorModel.swift:330` if ids are now user-visible under the new naming · REL-12
- [ ] Write the non-affiliation disclaimer and place it in the app, the store description and the support page · REL-14
- [ ] Add a rights paragraph to the thirteen `Curves/*/SOURCES.md` files that lack one · REL-15
- [ ] Replace or state the rights position for the CineStill storefront-image source · REL-15
- [ ] Add a root `LICENSE` · REL-16
- [ ] Add `NOTICE.md` discharging the CIE CC BY-SA 4.0 attribution · REL-15, REL-16
- [ ] Add an Acknowledgements screen to `FilmApp/SettingsView.swift` · REL-16
- [ ] Delete or replace the six PR-evidence PNGs containing Apple's sample photograph · REL-17
- [ ] Source and record the rights for the store screenshot imagery · REL-17, REL-38
- [ ] Have counsel review the chosen trademark option and the datasheet-derivation position · REL-12, REL-15

**Build and bundle (these make an upload possible at all)**

- [ ] Create `FilmApp/Assets.xcassets` with an `AppIcon` set (light, dark, tinted) · REL-01
- [ ] Add the asset catalogue to the target and set `ASSETCATALOG_COMPILER_APPICON_NAME` in both configurations · REL-01
- [ ] Set `MARKETING_VERSION = 1.0` and `CURRENT_PROJECT_VERSION = 1` in both configurations · REL-02
- [ ] Set `INFOPLIST_KEY_CFBundleDisplayName = Dye` in both configurations · REL-03
- [ ] Set `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` (and `_iPad` if iPad ships) · REL-04
- [ ] Set `INFOPLIST_KEY_UIRequiredDeviceCapabilities = metal` · REL-04
- [ ] Set `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` · REL-04, REL-40
- [ ] Set `INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.photography` · REL-04
- [ ] Add a launch-screen background colour matching `#050505` · REL-04, REL-24
- [ ] Set `TARGETED_DEVICE_FAMILY` to match the Q3 decision · REL-05
- [ ] Add `FilmApp/PrivacyInfo.xcprivacy` with empty tracking/API/data arrays and add it to the Resources phase · REL-07
- [ ] Commit `FilmApp.xcodeproj/xcshareddata/xcschemes/FilmApp.xcscheme` with Archive pinned to Release · REL-06, REL-34
- [ ] Move `DEVELOPMENT_TEAM` into an `.xcconfig` · REL-37
- [ ] Set `DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"` for Release explicitly · REL-35

**Engineering — correctness and crash risk**

- [ ] Replace the force unwrap at `Sources/FilmEngine/Profiles/Profile.swift:62-63` with a thrown error · REL-06
- [ ] Replace the force unwrap at `Sources/FilmEngine/Renderer.swift:44` with a thrown error · REL-06
- [ ] Build a Release archive and confirm the three SPM resource paths exist inside the `.app` · REL-06
- [ ] Create the SwiftData `ModelContainer` with `try` and an in-memory fallback · REL-32
- [ ] Add `VersionedSchema` and a `SchemaMigrationPlan` stub for `Preset` · REL-32
- [ ] Verify a v1 → v2 schema change preserves saved Presets · REL-32
- [ ] Re-run `docs/audits/film-stock-accuracy-probe.py` and fix the colour grain reference coordinate · REL-20
- [ ] Add renderer tests over shipped colour Profiles asserting a non-zero grain envelope · REL-20
- [ ] Update the Golden Images on a Metal-capable Mac · REL-20
- [ ] Size `ExportOptions.textureBudgetBytes` from `os_proc_available_memory()` · REL-29
- [ ] Stop holding the assembled frame and the encoded `Data` simultaneously · REL-29
- [ ] Evict thumbnail caches before starting an Export · REL-29
- [ ] Measure a 48 MP Export in all three formats on an A12-class device with Instruments · REL-29
- [ ] Sweep `tmp/` on launch and delete the previous Export when a new one starts · REL-30
- [ ] Precompile the Metal library into a `.metallib` instead of `makeLibrary(source:)` · REL-33
- [ ] Add a timeout, progress and a Cancel to the iCloud photo-download path · REL-33
- [ ] Wrap the Export in `beginBackgroundTask` and handle expiry · REL-33
- [ ] Add `MetricKit` diagnostics · REL-35
- [ ] Deduplicate the CineStill 800T payloads against Vision3 500T · REL-41

**Engineering — behaviour, copy and accessibility**

- [ ] Render and write the Export before requesting Photos authorisation; keep Share on denial · REL-10
- [ ] Merge this audit with `security.md` and `performance.md` into one reconciled work list · REL-11
- [ ] Split the corrupt-file and untagged-file errors and offer "Open as sRGB" · REL-28
- [ ] Fix SEC-01, SEC-02 and SEC-04 on the decode path alongside REL-28 · REL-11, REL-28
- [ ] Add a `FilmError` presentation layer so no engine identifier reaches the UI · REL-31
- [ ] Restore the Approximation qualifier at all seven naming sites and the Exported LUT header · REL-18
- [ ] Extract the qualifier into one place and add a test that asserts every naming site uses it · REL-18
- [ ] Decide whether `spectral.contrastFilters` alone should qualify a whole Profile, and update `CONTEXT.md` if not · REL-18
- [ ] Surface per-parameter Provenance in the Film Stock browser · REL-19
- [ ] Hide or explain the five synthetic studies, and add an explicit Catalogue sort order · REL-23
- [ ] Fix `"Stock"` → `"Film Stock"` at `Parameter.swift:303`, `:305`, `:734` · REL-27
- [ ] Apply the Q7 spelling decision to the user-facing strings · REL-27
- [ ] Fix `Cinestill` → `CineStill` if the brand names survive Q1 · REL-27
- [ ] Correct the "grouped by Process" claim in `README.md` · REL-23
- [ ] Add an `accessibilityLabel` and a Delete accessibility action to the Preset row · REL-25
- [ ] Raise `textQuaternary`, and stop using `textDisabled` for the Contact Sheet legend · REL-25
- [ ] Add a Privacy Policy, Support and Acknowledgements section to `FilmApp/SettingsView.swift` · REL-09, REL-16, REL-39
- [ ] Proofread all user-facing strings on device at default and `accessibility5` sizes · REL-27
- [ ] Add a `Localizable.xcstrings` catalogue and `SWIFT_EMIT_LOC_STRINGS = YES` · REL-26

**Verification (nothing below can be skipped by reasoning about it)**

- [ ] Run the full REL-33 edge-case matrix on an A12-class device and record the results · REL-33
- [ ] Run the same matrix on a current device · REL-33
- [ ] VoiceOver pass: welcome → picker → browse → dial → compare → loupe → Preset save → Preset delete → Export · REL-25
- [ ] Dynamic Type pass at `accessibility5` on every screen · REL-25
- [ ] Reduce Motion, Reduce Transparency and Increase Contrast passes · REL-25
- [ ] Rotation pass in every allowed orientation · REL-04
- [ ] iPad pass including Split View and Stage Manager, if iPad ships · REL-05
- [ ] Cold-launch pass with no white flash and an acceptable time to first frame · REL-04, REL-33
- [ ] Deny Photos add permission and confirm Export still completes and shares · REL-10
- [ ] Ten consecutive Exports, then check Settings → iPhone Storage · REL-30

**Release engineering**

- [ ] Add a CI job that builds a Release archive on `main` · REL-34
- [ ] Add a tag-gated signed archive and TestFlight upload job · REL-34
- [ ] Add a launch smoke test (XCUITest) to CI · REL-34
- [ ] Add an `accessibility5` snapshot check to CI · REL-25, REL-34
- [ ] Archive dSYMs as a CI artefact keyed by build number · REL-35
- [ ] Adopt the versioning scheme and tag the first submitted build · REL-36
- [ ] Add `CHANGELOG.md` · REL-36
- [ ] Promote this checklist into `docs/release.md` · REL-36
- [ ] Push a signed build to TestFlight and install it from the TestFlight app · REL-37
- [ ] Run the whole reviewer path on the TestFlight build · REL-06, REL-33

**Store listing (do this last — Q1 and Q6 determine most of it)**

- [ ] Publish the privacy policy at a stable URL · REL-09
- [ ] Publish the support page at a stable URL · REL-39
- [ ] Reserve the app name in App Store Connect and confirm availability · REL-13, REL-40
- [ ] Create the App Store Connect record for `app.memoji.dye` · REL-37
- [ ] Accept the required Apple agreements · REL-37
- [ ] Complete the App Privacy questionnaire as "Data Not Collected", tracking No · REL-08
- [ ] Complete the age-rating questionnaire · REL-40
- [ ] Set the category to Photo & Video · REL-40
- [ ] Write the subtitle with no third-party marks · REL-13
- [ ] Write the keyword field with no third-party marks · REL-13
- [ ] Write the description using "physically motivated models", never "accurate" · REL-19, REL-40
- [ ] Describe the Contact Sheet and the Exported LUT so they are not undocumented features · REL-40
- [ ] Set the price per the Q2 decision · REL-22, REL-40
- [ ] Capture the 6.9" iPhone screenshot set against `HEAD`'s UI with rights-cleared imagery · REL-38
- [ ] Capture the 13" iPad screenshot set, if iPad ships · REL-05, REL-38
- [ ] Write the App Review notes: photos needed, Photos add permission, and the trademark position · REL-40
- [ ] Confirm the export-compliance answer matches the plist · REL-40
- [ ] **Re-verify every *(recalled)* claim in this audit against the current App Review Guidelines and Xcode documentation before submitting** · Method and limits
- [ ] Submit for review

---

*End of audit. Findings REL-01 through REL-41.*
