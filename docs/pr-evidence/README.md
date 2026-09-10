# PR evidence

Screenshots attached to pull requests, kept so a design decision can be re-read
later against what it actually looked like.

## Rights

**Every capture in this directory must use imagery whose rights are recorded here.**
Two directories previously held six full-resolution PNGs of the magenta ice-plant
flower field, which is Apple's own iOS simulator sample photograph. Apple licenses
that media for use *within* Xcode and the simulator; republishing it as PNGs on a
public repository is a stretch, and using it in an App Store screenshot would be a
clear problem. The six were removed rather than left in place. They are still in the
git history — this is a rights hygiene fix, not an attempt to unpublish anything.

Use one of:

- a photograph you own, with the origin recorded in the directory's `README.md`;
- an explicitly licensed image, with the licence recorded and any model release
  noted if a person is recognisable;
- a render of the **Contact Sheet Reference**, which
  `Sources/FilmEngine/ContactSheetReference.swift` builds procedurally from a
  hardcoded patch array. It reads no file and decodes no image, so there is no
  ownership question at all. This is the default choice.

Never use simulator sample media. Never use a manufacturer's logo, packaging,
canister or brand colours. The same rules govern the App Store screenshots — see
`docs/release.md`.

## Capturing

`xcrun simctl io booted screenshot`, from a device whose size is recorded alongside
the capture. Record the commit as well: `docs/pr-evidence/identity-rail/` went stale
against `HEAD` without anyone noticing, and stale evidence is worse than none.
