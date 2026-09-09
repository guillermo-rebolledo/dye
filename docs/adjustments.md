# The Adjustment Pass

The Adjustments are the controls a photo editor offers over a finished picture —
Brilliance, Highlights, Shadows, Contrast, Brightness, Black Point, Saturation and
Vibrance — and the Adjustment Pass is where Dye applies them. It runs at Pass 11,
after the Output Stage and before Geometry, and it acts on the positive the scan or
the print returned, on the Transparency for a reversal Stock, or on the Working
Space itself for the identity Profile. It never acts on the light before the film.

That placement is the whole design. A photographer who scans a negative and opens
the scan in an editor is doing exactly this: the film has already decided what it
kept, and the editor works with that. Highlights in this app therefore recovers a
highlight only as far as the Stock's own shoulder left anything to recover, and
Shadows opens only what the emulsion recorded. The controls that *do* change what
the film received — Exposure, Temperature and Tint — already exist on the Light
stage and are deliberately not repeated here under a photo editor's names.

Neutral settings do not run the Pass at all, so every Golden Image, Step Wedge and
Contact Sheet renders byte-identically to before it existed.

## Settings

```swift
RenderSettings.adjustments: Adjustments   // all eight default to 0
Adjustments.range == -1.0...1.0
```

Every control is bipolar, −1…1, and the app shows it as ±100. `isNeutral` is what
the renderer keys the Pass off. A Preset written before the Pass existed has no
`adjustments` key and decodes as neutral; one that names only some of the eight
decodes the rest as zero.

## The tone curve

The six tone controls compose one curve in the display encoding — the sRGB
transfer function, continued above one so light past diffuse white survives —
applied to each channel, which is what a photo editor's RGB tone curve is. Each
term is a polynomial in the value clamped to 0…1 with zeros at black and white, so
the curve holds the two ends still wherever a control says it does, stays
monotone across the whole control range, and leaves a value outside 0…1 alone
rather than extrapolating it. In the order applied, with `c = clamp(x, 0, 1)`:

| Control | Term | Notes |
| -- | -- | -- |
| Black point `b` | `x = max((x − 0.15b) / (1 − 0.15b), min(x, 0))` | +1 crushes encoded 0.15 and below into black itself, never past it; −1 lifts black to encoded 0.13 |
| Brightness `k` | `x += 0.5k · c(1 − c)` | peaks at mid-grey |
| Shadows `s` | `x += 0.5s · c(1 − c)²` | peaks a third of the way up |
| Highlights `h ≥ 0` | `x += 0.5h · c²(1 − c)` | peaks two thirds of the way up |
| Highlights `h < 0` | `x = 0.5 + d / (1 + |h|d)` for `d = x − 0.5 > 0` | a C¹ knee: light past white comes back under it |
| Contrast `k` | `x += 2k · (c − 0.5) · c(1 − c)` | slope 1.5 at mid-grey at +1, 0.5 at −1, a toe and a shoulder at the ends |

Highlight recovery is the one term that is not a polynomial, because its purpose is
to bring light from above white back below it and a term that vanished at white
could not. The knee's slope is exactly one at mid-grey, so nothing below it moves.

**Brilliance is not a term.** It is the three moves an editor makes to bring detail
forward — open the shadows, pull the highlights back, add a little contrast in the
middle — made together, so the renderer resolves `brilliance = v` to
`shadows += 0.6v`, `highlights −= 0.5v`, `contrast += 0.3v` and the shader never
sees it. The sums are clamped to where each term stays monotone: shadows and
highlights to ±1.5, which their curves tolerate, and contrast to ±1, which is where
its curve's slope reaches zero at the ends.

`AdjustmentsTests.theToneCurveStaysMonotoneAtEveryExtreme` renders a 0…2 ramp
through every corner of the control space and asserts it never decreases.

## Colour

After the curve the value returns to linear light and the two colour controls act
on chroma about Rec.2020 luminance, `Y = 0.2627R + 0.6780G + 0.0593B`, which
scaling chroma holds exactly.

**Saturation** `s` scales chroma by `1 + s`: −1 is a neutral grey at the same
luminance, +1 doubles it. This is not a Monochrome Collapse, which weighs the
colours the way a Stock's emulsion does rather than all the same.

**Vibrance** `v` scales chroma by `1 + v(1 − saturated)(1 − 0.75 · skin)` when
positive and by `1 + v` when negative. `saturated` is `(max − min) / max`, so a
boost goes to the muted colours and a colour already vivid takes almost none of
it. `skin` is a bump over the hue band with red on top and green above blue,
about 10°–50°, so a face is protected from most of a boost; a cut is a plain
desaturation and protects nothing.

## What it is not

It is per-pixel, so an Exported LUT carries it whole, the LUT's title says
`adjusted` when it does, and a Tile needs no Apron for it. It runs before
Geometry, so a Black Point lift raises the scan's black and leaves the Frame
Border's rebate unexposed: the frame is adjusted, the film around it is not. And
it is not a place to reach the film from — a Contrast of +100 through Portra is
Portra's scan with a steeper curve over it, not a different development.
