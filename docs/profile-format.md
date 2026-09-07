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

All radii remain in film-plane microns. At render time the conversion will be
`radiusMicrons / (format.frameWidthMM * 1000) * imageWidth`. Format widths are
36 mm (135), 56 mm (120, nominal 6×6), and 120 mm (4×5, exposed long edge).
A future format/aspect extension can refine these nominal frame widths.

## Binary layout

| Bytes | Meaning |
| --- | --- |
| 0–7 | ASCII `FILMPROF` |
| 8–11 | Little-endian UInt32 version, currently 1 |
| 12–15 | Little-endian UInt32 UTF-8 JSON header length |
| 16… | JSON `{profile: FilmProfile, payloads: [{name, offset, length}]}` |
| after JSON | Contiguous payload bytes; offsets relative to this point |

A Colour Cube is red-fastest, then green, then blue, RGBA little-endian float16;
its byte length is `lutSize³ × 8`. The standard baked size is 33. Calibration
cubes may use sizes 2…65. A Density Curve is 1024 little-endian float16 values,
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
renamed Display Names cannot accidentally reuse stale textures. The app picker
lists the bundled synthetic studies by Process; selection is data-only in MEM-241.
