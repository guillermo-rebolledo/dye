# The Grain Pass

Grain is the developed Emulsion's own structure, so it belongs to the negative
rather than to the picture of it. It runs at Pass 8, in **Density Space** — after
the Film Response and before the Output Stage — which is what makes the scan or
the print act on it the way it would on real film. Grain added after the Output
Stage would be noise laid on a positive, and would not compress in the highlights
the way a scan compresses everything else the negative carries.

## Profile parameters

```json
"grain": {
  "model": "dye-cloud", "rmsGranularity": 0.008, "grainRadiusMicrons": 1.2,
  "densityResponse": [ 32 entries ], "channelCorrelation": 0.15,
  "channelRadiusScale": [1, 0.85, 0.7]
}
```

`rmsGranularity` is the RMS density fluctuation measured through the standard
48 µm aperture — the figure a datasheet publishes, in density units.
`grainRadiusMicrons` is the crystal or dye-cloud radius in **Film-Plane Microns**,
scaled per channel by `channelRadiusScale`. `densityResponse` is the 32-entry
**Density Response**, sampled from the Stock's base density to twice its mid-grey
density. `channelCorrelation` sits near zero for colour negative, where the three
Emulsion layers grain independently, and near one for a black & white silver
Stock, which has one layer. `model` is not yet read at render time: `procedural`
is what ships, and the `dye-cloud` and `stochastic` models are later work.

## The pass

1. **Size the field from the film, not the pixel grid.** A channel's noise cell is
   `2 × grainRadiusMicrons × channelRadiusScale`, converted to pixels through Frame
   Width exactly as the Halation radii are. Frame Width is the frame's long edge, so
   a portrait photograph records it down its height.
2. **Floor the cell at the sampling pitch.** One pixel of a 2048-pixel Preview
   covers 17.6 µm of a 36 mm frame, so it cannot resolve a 1.2 µm crystal at all:
   what it records is the fluctuation *within* that pixel. Below the pitch the cell
   is one pixel and the amplitude, not the size, is what carries the Stock's
   granularity — and one pixel then holds one independent sample, because
   neighbouring pixels of unresolved grain share no crystals. Every Stock in the
   Catalogue is in this regime at any practical output size; a 1.2 µm crystal on a
   36 mm frame would need 30 000 pixels to resolve.
3. **Scale the amplitude by Selwyn's law.** Granularity is inversely proportional to
   the diameter of the aperture it is measured through, so `sigma = rmsGranularity ×
   48 µm / aperture`, where the aperture is the larger of the pixel pitch and the
   grain itself. This is why a full-resolution Export is visibly grainier than a
   Preview of the same frame and the same Stock: it is not a different film, it is
   the same film measured through a smaller hole.
4. **Modulate by the Density Response.** The signal is normalised so the Stock's base
   density is the curve's first entry and its mid-grey density its midpoint. Grain is
   loudest in the midtones and quiet in deep shadow and blown highlight, which is
   what separates emulsion from noise added to the whole frame. Getting this curve
   right matters more to how the result looks than the choice of noise algorithm.
5. **Decorrelate the channels.** Each channel takes `sqrt(1 − channelCorrelation)`
   of its own field and `sqrt(channelCorrelation)` of one shared between all three,
   a split that preserves variance, so the parameter reads as the correlation it
   names.
6. **Apply it as density.** A Density Space signal takes the fluctuation directly.
   A Colour Cube that already carries the Baker's scan has returned a positive, so
   the same extra density is a transmission the light passes through: `value ×
   10^−density`.

The noise itself is smoothstep-interpolated value noise from an integer hash of the
**global** pixel coordinate, so a later tiled Export samples one field from any tile
origin rather than repeating a pattern per Tile. `RenderSettings.seed` fixes the
field; the same seed renders the same frame, which is what makes Golden Images
possible with Grain on.

`RenderSettings.grainIntensity` scales the Profile's granularity. It defaults to 1 —
the Stock's own value — and the app exposes it as a 0–200% control. Zero skips the
Pass entirely, which is also what the Baker's Step Wedges do, because a wedge
measures the curve rather than the fluctuation around it.

## What the tests assert

`Tests/FilmEngineTests/GrainTests.swift` goes through the public renderer entry
point. An identity Colour Cube isolates the Pass, and the field it added is read as
the difference between a render with Grain and the same render without it.

- The same scene at 512, 1024 and 2048 pixels decorrelates over the same fraction of
  the frame, a portrait frame grains as a landscape one, and a Stock with crystals
  twice as wide decorrelates twice as far. The test Profile's grain is far coarser
  than any real Emulsion, because a field has to be resolvable for its size to be
  measurable at all.
- Zero intensity leaves the frame bit-identical; 200% doubles the amplitude.
- Mid-grey is the loudest part of the Density Response, and base density and twice
  mid-grey are both quiet.
- `channelCorrelation` of 0, 0.5 and 1 produce that cross-channel correlation.
- Through a `scan` Output Stage the fluctuation arrives multiplied by the Scan's own
  slope at that density, which is how the Pass's position in the pipeline is pinned.
- In the shipped regime — grain finer than a pixel — halving the pixel pitch
  doubles the amplitude, neighbouring pixels are uncorrelated, and the amplitude at
  a known pitch is the published figure carried by Selwyn's law.
- The seed fixes the field without changing its amplitude.
