# Cinestill 800T Curve Set

Cinestill 800T is Kodak Vision3 500T with the **Remjet** anti-halation backing
removed so the film can be run through C-41. It is the same **Emulsion**, so it is
the same Profile: this directory holds no CSVs and no spectral model of its own.
It is a derivation of [`vision3-500t`](../vision3-500t/SOURCES.md), and the
Colour Cubes the Baker emits for it are byte-identical to that Stock's.

## What the derivation may change

`stock.json` here is an override document, not a Profile. The Baker accepts only
`derivedFrom`, `id`, `displayName`, `process`, `nominalISO`, `trueISO`, `halation`
and `provenance`; `provenance` merges key by key and everything else replaces.
Anything the Colour Cubes are baked from — the Characteristic Curves, the spectral
tables, the shaper, the Development Offsets, MTF, Grain — has to stay with the
parent, so a derivation cannot quietly become a different film. The Baker's source
fingerprint covers the parent Curve Set **and** this override document, so a change
to either invalidates a Profile baked from the other.

- `halation`: the whole point. Vision3 500T's Remjet backing absorbs the light
  that reaches the base; without it that light reflects and re-exposes the
  emulsion from behind. `strength` goes from 0.008 to 0.55, the red radius from
  180 µm to 420 µm, and the `tint` narrows towards red. **All four numbers are
  artistic.** Halation strength is published by nobody, and Cinestill publishes no
  sensitometric datasheet. They are tuned so a practical light in frame reads as the
  burning red halo this Stock is known for, and the Provenance says so.
- `nominalISO` 800: the Box Speed. Cinestill prints "800Tungsten / ISO 800" on the
  135 packaging and states it on the product page,
  https://cinestillfilm.com/products/800tungsten-800t-color-film, retrieved
  2026-09-07. That listing is the cited source, and it is the only measured claim
  this file makes.
- `trueISO` 500: the parent Emulsion's Exposure Index. The parent marks its own
  True Speed measured because Kodak publishes EI 500; here the same number is
  marked **artistic**, because what a Remjet-free ECN-2 emulsion actually meters
  at through C-41 is not something either manufacturer publishes.
- `process` `c41`: what the film is sold to be developed in.

## What this Profile does not model

The sensitometry is Kodak's **ECN-2** sensitometry. C-41 is a different process
with a different developer, time and temperature; it changes contrast and the mask,
and rating the roll at 800 is a push relative to the emulsion's 500. None of that
is modelled here. Nor is the halo's spatial structure derived from anything
measured: the pass is a Gaussian scattering kernel, not a ray-traced base.

The claim this Curve Set makes is narrow and worth stating plainly: **it models
Remjet removal, and nothing else about the difference between these two products.**

## Stock Balance

Both Stocks are balanced for 3200 K tungsten. A daylight scene therefore records
blue, and the renderer does not correct it — that cast is the Stock behaving
correctly. Matching the White Balance control to 3200 K makes the Pass an exact
pass-through.
