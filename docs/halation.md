# The Halation Pass

Halation is light that passes through the Emulsion, reflects off the back of the
film base and re-exposes the Emulsion from behind. It is an **exposure**
phenomenon, so it runs at Pass 5 — after White Balance, Exposure and Reciprocity,
and **before** the Film Response. Applying it after the density curves is the
common mistake in this domain and is immediately visible: the halo it adds
scales linearly with its own strength, where real Halation is compressed by the
curve the way any other light is. Bloom, which is lens diffusion and a different
phenomenon, still has no Pass and no Profile parameter.

## Profile parameters

```json
"halation": { "strength": 0.55, "threshold": 1.1, "radiusMicrons": [420, 150, 70], "tint": [1, 0.18, 0.08] }
```

`strength` is the fraction of above-threshold light scattered back, 0…1.
`threshold` is the Working Space value the knee is centred on. `radiusMicrons` is
the per-channel scattering sigma in **Film-Plane Microns**, and must not increase
from red to blue: longer wavelengths penetrate further through the base, which is
why the halo is red. `tint` weights the scattered light per channel, 0…1. Every
one of these is `artistic` in practice — no manufacturer publishes them.

Radii convert to pixels at render time as `radiusMicrons / (frameWidthMM * 1000) *
max(imageWidth, imageHeight)`, so the halo covers the same fraction of the frame at
any resolution and in either orientation — Frame Width is the frame's long edge,
which a portrait photograph records down its height. A 220 µm red radius on a 36 mm
frame at 8000 pixels is about 49 pixels, which is why this cannot be a single-pass
Gaussian.

`RenderSettings.halationIntensity` scales the Profile's `strength`. It defaults to
1 — the Stock's own value — and the app exposes it as a 0–200% control. Zero skips
the Pass entirely, which is also what the Baker's Step Wedges do, because
neighbouring wedge samples are unrelated exposures rather than adjacent points in
one scene.

## The pass

1. **Threshold with a smooth knee.** Per channel, across ±half the threshold, a C1
   quadratic joins zero to `value − threshold`. A hard cutoff would make a
   highlight's halo switch on as it crosses, which reads as an outline.
2. **Blur in a pyramid**, kept in float16 like every other intermediate. Each level
   is blurred with a separable Gaussian of 1.5 texels, then halved with a 2×2 box
   average to produce the next. The pyramid is exactly as deep as the widest
   requested radius needs — five or six levels at photographic sizes, fewer for a
   small Preview, more only when a full-resolution frame asks for a halo six could
   not carry, and never deeper than the image allows, since a level collapsed to one
   texel carries no radius. Nine levels reach a 449-pixel sigma; past that a radius
   clamps.
3. **Weight per channel per level.** Each level has a known effective sigma in
   level-0 pixels — its own blur plus every downsample and blur that produced it —
   running from 1.5 pixels upward. A channel's target sigma is split between
   the two neighbouring levels so the mixture carries the requested **variance**.
   The unblurred extract is the pyramid's zero-sigma level, so a radius below one
   blur step still resolves rather than clamping. Weights sum to one per channel,
   so the blur is energy preserving: the frame gains exactly the scattered
   fraction of the above-threshold light.
4. **Accumulate coarse to fine.** Each level is added to a bilinear 2× upsample of
   the level above it. Doubling once per level keeps the interpolation local; the
   32× magnification of the smallest level in one step is what would band.
5. **Tint and composite** back into the linear signal, which the Film Response
   then reads as light.

## What the tests assert

`Tests/FilmEngineTests/HalationTests.swift` goes through the public renderer entry
point, never an individual pass. An identity Colour Cube isolates the scattering
itself; the shipped Cinestill 800T Profile is the stress case.

- The knee matches the specified C1 quadratic, is exactly zero below it, and its
  slope stays inside 0…1 without stepping.
- Red reaches furthest, then green, then blue, each falling monotonically, and the
  frame gains the scattered fraction of the above-threshold light to within 2%.
- The same scene at four resolutions, spanning four pyramid levels, scatters across
  the same fraction of the frame, and a portrait frame scatters as far as a
  landscape one.
- Cinestill 800T at 200% shows no banding: along the radius, horizontally,
  vertically and diagonally, at 512, 1024 and 2048 pixels, the falloff never rises,
  never holds the same value for more than two samples, and never steps by much
  more than its own average.
- Doubling the intensity does not double the result, at a sample well away from the
  top of the range. A post effect would add linearly; this is exposure being
  compressed by the density curves that follow it.
- Cinestill 800T's Colour Cubes are byte-identical to Vision3 500T's, the two
  Stocks render identically below both thresholds, and a daylight scene through
  either records blue.
