# Design handoff: the Dye editor

Two files, and they answer different questions.

- [`one-rail-redesign.md`](one-rail-redesign.md) — **the spec.** A delta against the
  shipped editor: what the rail replaces, the geometry, the states, and what is
  deliberately left alone. Read this first.
- [`Dye Editor - one rail.html`](Dye%20Editor%20-%20one%20rail.html) — **the
  reference.** Screens `3a`–`3d` in iPhone frames, `3a` interactive. Open it in a
  browser.

The HTML is a design reference written in HTML, not production code. Do not port
it, its runtime, or its CSS. The photograph in every frame is a synthetic
placeholder and the per-stock renders are filter approximations; the real
renderer produces the actual pixels. Colours, type sizes, control heights and
spacing, however, are final and are meant to be matched.

The reference is the source of truth for *appearance*. The engine is the source
of truth for *behaviour*, and where the two disagree the engine wins.

[`../docs/editor-redesign.md`](../docs/editor-redesign.md) is the implementation
spec for the fixed-deck editor that shipped before the rail, and it records where
that handoff and the engine disagreed and how each conflict was resolved.
