# The Bloom Pass

Bloom is the taking lens spreading a fraction of the light across the frame —
veiling glare, scattered in the glass and off the barrel — as distinct from
Halation, which is light reflecting off the back of the film base. It runs at
Pass 5, before Halation, because that is the order the light meets them: the lens
diffuses the scene, then the film records it and reflects part of it back into
itself.

The two phenomena are structurally different, not the same effect at two settings:

|  | Bloom | Halation |
| -- | -- | -- |
| Source | the taking lens | the back of the film base |
| Threshold | none — all light diffuses | a knee above `halation.threshold` |
| Colour | neutral | tinted, red-weighted |
| Radius | one | per channel, red furthest |
| Energy | redistributed: what blooms is taken from the source | added: a second exposure of the frame |

That last row is what makes Bloom visible as *lowered* micro-contrast around a
highlight rather than as extra light: a lens cannot hand the film more light than
it received.

## Profile parameters

```json
"bloom": { "strength": 0.02, "radiusMicrons": 900 }
```

`strength` is the fraction of the light the lens diffuses, 0…1. `radiusMicrons` is
the sigma it diffuses over, in **Film-Plane Microns**, so the glare covers the same
fraction of the frame at any output resolution.

**Bloom is a property of the lens, not of the Stock.** It lives in the Profile only
so the user's control has a physically motivated default to scale, which is what
`CONTEXT.md` asked for when it recorded Bloom as having no home. Every real Stock in
the Catalogue therefore carries the same modelled lens — 2% at 900 µm, a decently
multicoated one — and both parameters are always `artistic`. The synthetic studies
and the identity calibration Profile carry zero, as their Halation does.

`RenderSettings.bloomIntensity` scales it, defaults to 1, and the app exposes it as a
0–200% control. Zero skips the Pass entirely, which is also what the Baker's Step
Wedges do.

Above 100%, a quadratic creative boost raises diffusion to at least 30% at
200% (capped at 100% to conserve light). The 0–100% range still scales the
profile linearly. A profile with zero diffusion stays disabled.

## The pass

Bloom and Halation share one set of kernels and one **Scattering Pyramid** design,
because after the extract they do the same thing: blur in a float16 pyramid, weight
each level so the mixture carries the requested variance, accumulate coarse to fine.
See [the Halation Pass](halation.md) for that machinery, which is unchanged. Bloom
differs in exactly two places:

1. **The extract takes everything.** A zero threshold with the narrowest knee passes
   every positive value through, so what is blurred is the whole frame rather than
   its highlights. Negative light — an out-of-gamut Working Space value — clamps to
   zero, because a lens cannot diffuse light it never received.
2. **The composite replaces rather than adds.** `out = in × (1 − strength) +
   scattered × strength`, against Halation's `out = in + scattered × strength ×
   tint`. Both are energy preserving; only Bloom's takes its share from the source.

The two Passes keep separate pyramids, because their radii resolve to different
depths and one allocation cannot serve both.

## What the tests assert

`Tests/FilmEngineTests/BloomTests.swift` goes through the public renderer entry
point, with an identity Colour Cube isolating the Pass.

- Bloom conserves energy: the frame's total light is unchanged to within a fraction
  of a percent, where Halation adds light to it.
- A bright point loses to its surroundings exactly what the surroundings gain, and
  the falloff is neutral — all three channels alike — where Halation's is red.
- The glare covers the same fraction of the frame at 512, 1024 and 2048 pixels, and
  a portrait frame blooms as a landscape one.
- Zero intensity leaves the frame bit-identical; 50–100% doubles the light moved,
  and the range above 100% provides a stronger creative boost.
- Bloom reaches the Emulsion before the density curves: doubling the intensity does
  not double the result through a Stock's Film Response.
