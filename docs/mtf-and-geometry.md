# The MTF and Geometry Passes

Two spatial passes bracket the film. **MTF** is Pass 6, on the light before the
Film Response: it is the Emulsion's own micro-contrast, which is why a fine-grained
tabular Stock reads as sharper than a coarse cubic one at the same resolution.
**Geometry** is Pass 10, after the Output Stage: the lens's falloff, the gate's
unsteadiness and the frame's edge, none of which is a property of the Stock.

## MTF

```json
"mtf": { "cyclesPerMM": [3, 5, 10, 20, 30, 40], "response": [1.06, 1.09, 1.17, 1.11, 0.89, 0.74] }
```

A published MTF is measured in cycles per millimetre **on the film**, so it is fixed
relative to the frame and converts to pixels through Frame Width exactly as the
Halation and Grain radii do. A curve above one at low frequency is not a digitising
error: it is the adjacency effect of development, and the Pass has to be able to
raise micro-contrast rather than only lose it.

The curve is realised as the signal itself plus two separable Gaussian blurs. A
Gaussian's response is a Gaussian in frequency, so `c0 + c1 G(fine) + c2 G(coarse)`
spans both a roll-off and an adjacency lift, and the renderer solves for `c` by
least squares against the published points, with `c0` taking the remainder so the
weights sum to one and a flat field cannot change value.

Two details are load-bearing:

- **The fit uses the discrete kernel the shader actually convolves**, not the
  continuous `exp(−2π²s²f²)`. Below about one pixel of sigma a sampled Gaussian
  departs from the continuous one badly enough to miss the published curve by 0.4.
- **Points above Nyquist are dropped.** A 1024-pixel frame across 36 mm carries
  14 cycles/mm at Nyquist, so a curve published from 20 cycles/mm upward says
  nothing about it. If no point survives, or the response is flat, the Pass does not
  run at all and the frame is untouched. This is why the identity Profile — the
  calibration seam, where the round trip must stay bit-exact — carries a flat curve.

## Geometry

Three controls, all of them the user's rather than the Stock's, and all of them zero
by default. Their sizes are in Film-Plane Microns, so each is the same fraction of
the frame at any output resolution.

- **Vignette** falls off as cos⁴ of the angle off axis — a lens's own falloff — with
  the radius measured to the corner of the frame, so it is a circle on the film
  rather than an ellipse in pixels. At full strength the corners cost two stops.
- **Gate weave** displaces the frame by up to 200 µm, sampled bilinearly. The
  displacement is fixed by `RenderSettings.seed`: a still frame weaves once rather
  than shimmering.
- **Frame border** blacks out up to 1.5 mm of unexposed rebate around the frame.

## What the tests assert

`Tests/FilmEngineTests/MTFTests.swift` renders sinusoidal gratings at stated
frequencies on the film and measures their modulation, the way a published curve is
measured. A Gaussian response is reproduced to within 0.05 across the whole usable
range; Portra's published adjacency lift raises micro-contrast above one; the same
frequency loses the same contrast at 1024 and 4096 pixels; and a flat or
unresolvable curve leaves the frame bit-identical.

`Tests/FilmEngineTests/GeometryTests.swift` asserts the two-stop corner falloff and
its circular shape at three frame shapes and sizes, that the border and the weave
displacement are the same fraction of the frame at every resolution, that the seed
fixes the displacement, and that the Pass does not run until something asks it to.
