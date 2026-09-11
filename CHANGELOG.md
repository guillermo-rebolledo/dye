# Changelog

`MARKETING_VERSION` is the user-visible semantic version. `CURRENT_PROJECT_VERSION`
is a monotonic integer, driven by the CI run number so it cannot be forgotten. Every
submitted build is tagged `v<MARKETING_VERSION>+<CURRENT_PROJECT_VERSION>`. This file
is also the source for the App Store "What's New" text. See `docs/release.md`.

## Unreleased — 1.0

First release. Not yet submitted.

### The Catalogue ships under names of its own

The twelve Stocks that carried live commercial trademarks now ship under evocative
names, applied at every naming site rather than only in the Profile data. Profile ids
are unchanged, so saved Presets, Golden Images and the CI Step Wedge patterns are
unaffected.

| Profile id | Display Name |
| --- | --- |
| `portra-160` | Linen 160 |
| `portra-400` | Linen 400 |
| `tri-x-400` | Newsprint 400 |
| `t-max-100` | Graphite 100 |
| `vision3-50d` | Daylight 50 |
| `vision3-200t` | Tungsten 200 |
| `vision3-250d` | Daylight 250 |
| `vision3-500t` | Tungsten 500 |
| `provia-100f` | Meridian 100 |
| `velvia-50` | Vermilion 50 |
| `cinestill-800t` | Halogen 800 |
| `fomapan-100` | Ash 100 |

The five Contrast Filters are named by colour and depth instead of by a trademarked
filter number, and the Export filename derives from the Display Name rather than the
Profile id.

### Honesty

- A Stock's name now carries its qualifier **everywhere the app names it**, not only
  in the Filmstrip. `FilmProfile.qualifiedDisplayName` is the single source, and a
  test fails when a new naming site reaches for the bare name.
- **Accuracy** is a new Profile field, distinct from **Provenance**. Every named
  Stock is `modelled` — built from published measurements, never compared with a
  photograph of the film — and says so. Nothing claims `validated`.
- The five synthetic studies sit together at the end of the Film Stock browser,
  behind a heading that says what they are: calibration patterns, not films.

### Bundle and release engineering

- App icon, asset catalogue, accent colour and launch background.
- Display name `Dye`, version `1.0`, build number from CI.
- iPhone only. The iPad declaration is dropped rather than left unearned.
- A privacy manifest declaring no tracking, no collected data and no
  required-reason API use.
- Orientations, required capabilities, category and export compliance declared.
- A shared scheme with Archive pinned to Release, an unsigned Release archive in CI,
  a script that asserts the bundle facts an upload rejects, and dSYMs retained.

### Robustness

- An Export whose Photos permission is denied still completes, still shows the file
  and still shares. Permission is asked for at the point of saving, not before the
  render.
- A photo with no colour profile can be opened as sRGB on the user's say-so. The
  decoder stays strict; the app takes responsibility for the assumption.
- An undecodable file, an unsupported format, an unsupported raw and an oversized
  photo each say something different and something a photographer can act on.
- Engine error strings no longer reach the screen. Each failure says what did not
  happen, with the engine's own words behind a Details disclosure.
- Saved Presets open in an explicit container with a versioned schema and a
  migration plan. A store that cannot be opened no longer crashes the app on launch.
- An Export no longer leaves a full-resolution copy of the photograph in the
  temporary directory. One scratch directory holds the current Export and nothing
  else, and it is emptied at launch.

### Accessibility

- A Preset can be deleted with VoiceOver, reads name-then-look rather than a
  concatenation, and its name field is labelled.
- Informational text no longer uses the disabled colour role; the fourth text step
  is above the 4.5:1 threshold.

### Legal

- `LICENSE` and `NOTICE.md`, discharging the CC BY-SA 4.0 obligation on the CIE data.
- About, Acknowledgements, Privacy Policy and Support in Settings. The policy and the
  support page are read on device, with no network — and the same words are published
  as two web pages for the App Store Connect fields that demand a URL. One source, and
  a test that fails when the two disagree.
