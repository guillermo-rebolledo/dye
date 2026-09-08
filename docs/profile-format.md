# Profile format, version 1

`FilmProfile` mirrors MEM-239's JSON schema. `id` and payload names are stable;
`displayName` is the only renameable user-facing field. `balance` is Stock Balance
in kelvin. `nominalISO` is Box Speed and `trueISO` is True Speed.

The five `process` values are `c41`, `e6`, `bw-silver`, `bw-chromogenic`, and `ecn2`.
Only B&W Profiles have `monochrome`; they reference a 1024-entry float16 Density
Curve and have no Colour Cubes. Colour Profiles have a nonempty, sparse
`colour.lutVariants` array of `{pushStops, lut}`. Offsets are unique finite values;
the array is not constrained to a fixed set of offsets. E-6 has Output Stage `none`.

Every physical parameter has a `provenance` marker (`measured` or `artistic`) keyed
by dotted JSON path. A vector or curve is one parameter. Paths include all fields
of colour, grain, halation, MTF and reciprocity, plus nominalISO, trueISO, balance,
format and, when present, monochrome. Identity fields are not physical parameters.
A missing required marker is an error. Measured means supported by a cited source;
all bundled study Profiles are synthetic and mark every parameter artistic.

All radii remain in film-plane microns. At render time the conversion is
`radiusMicrons / (format.frameWidthMM * 1000) * max(imageWidth, imageHeight)`:
Frame Width is the frame's long edge, which a portrait photograph records down its
height. Format widths are
36 mm (135), 56 mm (120, nominal 6×6), and 120 mm (4×5, exposed long edge).
A future format/aspect extension can refine these nominal frame widths.

`bloom.strength` is 0…1 and `bloom.radiusMicrons` at most 5000. Bloom describes the
taking lens rather than the Stock and is always `artistic`; see
[the Bloom Pass](bloom.md).

`halation.strength` and each `halation.tint` component are 0…1, `halation.threshold`
is positive, and `halation.radiusMicrons` must not increase from red to blue: longer
wavelengths scatter furthest through the base. See [the Halation Pass](halation.md)
for what the renderer does with them.

`reciprocity.schwarzschildP` carries exactly three exponents, one per layer, each
greater than zero and at most one, and `reciprocity.thresholdSeconds` is
nonnegative. Below the threshold the
Stock obeys reciprocity exactly; above it each layer keeps
`(seconds / thresholdSeconds)^(p − 1)` of the light it is given. Three exponents
rather than one because the layers lose speed at different rates, which is why a
manufacturer's published long-exposure compensation is a colour-correction filter
as well as an extra stop. An exponent of 1 is a layer with no measured failure.

`grain.densityResponse` carries exactly 32 entries and `grain.channelRadiusScale`
exactly three, `grain.channelCorrelation` is 0…1, and `grain.rmsGranularity` is a
density measured through the standard 48 µm aperture. `mtf.cyclesPerMM` is strictly
ascending and the same length as `mtf.response`, which may exceed one where a
Stock's adjacency effect raises micro-contrast. See [the Grain Pass](grain.md) and
[the MTF and Geometry Passes](mtf-and-geometry.md) for what the renderer does with
them.

## Derived Profiles

A Profile that models another's Emulsion names it in `derivedFrom`. This is lineage
rather than a physical parameter, so like `colour.sourceFingerprint` it carries no
Provenance marker; it is absent from Profiles baked from their own Curve Set, and a
Profile may not derive from itself.

Its authoring directory holds a `stock.json` containing **only** overrides. The
Baker accepts `derivedFrom`, `id`, `displayName`, `process`, `nominalISO`,
`trueISO`, `halation` and `provenance`, reads every CSV and `spectral.json` from
the parent's directory, and rejects any other key. `provenance` merges key by key
so a derivation records only what changed; the rest replace. The resulting payloads
are byte-identical to the parent's, and the source fingerprint covers the parent's
files and the override document together.

Cinestill 800T derives from Vision3 500T this way: the same Emulsion without its
Remjet backing, differing in Halation, Box Speed and Process and nothing else.

## Binary layout

| Bytes | Meaning |
| --- | --- |
| 0–7 | ASCII `FILMPROF` |
| 8–11 | Little-endian UInt32 version, currently 1 |
| 12–15 | Little-endian UInt32 UTF-8 JSON header length |
| 16… | JSON `{profile: FilmProfile, payloads: [{name, offset, length}]}` |
| after JSON | Contiguous payload bytes; offsets relative to this point |

A Colour Cube is red-fastest, then green, then blue, RGBA little-endian float16;
its byte length is `lutSize³ × 8`. The Baker emits 33 or 65; 65 is for a Stock
whose Characteristic Curve turns faster than 33 nodes can follow between them,
which Velvia 50 does, and it costs eight times the payload. Calibration
cubes may use any size 2…65. A Density Curve is 1024 little-endian float16 values,
2048 bytes. Alpha is carried by the input, not taken from the Colour Cube.

The codec emits sorted JSON keys and sorts payloads by name for deterministic
bytes. It rejects unknown versions, truncated/overlapping payloads, missing or
extra payload references, unexpected trailing bytes, and invalid schema values.
Headers are limited to 4 MiB and files to 128 MiB. Full decode validates finite
payload values. Metadata-only loading validates the header and byte ranges;
actual payload values are checked when loaded for rendering.

`ProfileCatalogue.bundled()` reads only metadata at launch. The renderer lazily
uploads Colour Cubes and keeps the three most recently used textures by default.
Cache keys identify loaded content, so identical ids in different files and
renamed Display Names cannot accidentally reuse stale textures. The cache holds
four entries so a blended Development Offset keeps both neighbouring cubes warm.
The app picker lists the bundled Profiles by Process and renders the selection.

## Spectral extensions (MEM-243)

Optional `colour.inputShaper` contains `minimumLogExposure`, `maximumLogExposure`,
and `middleGrayLogExposure` in log10 lux-seconds. They are finite, ordered and
bounded to −10…10. With this shaper, `colour.cubeOutput` must be
`displayLinearRec2020`, the Profile must be colour, and Output Stage must be
`scan` — or `none` for E-6, whose cube carries the transparency itself rather than
a scan of a negative. A display-linear cube without a shaper is rejected. Absent extensions
retain the existing linear [0, 1] input / Density Space output contract.

The Baker adds `colour.sourceFingerprint`, a lowercase 64-character SHA-256
covering the model version and consumed source files. This is build identity,
not a physical parameter. It is absent from authoring metadata and study Profiles.
Both shaper and cube-output parameters require Provenance. Extra spectral
Provenance paths describe measured source arrays and artistic model parameters.

The binary payload layout is unchanged. The renderer applies the shaper at render
time and treats `displayLinearRec2020` cubes as already scanned, so the Scan
Output Stage passes them through. Density Space cubes with `outputStage: scan`
are inverted and auto-balanced by the renderer instead.
