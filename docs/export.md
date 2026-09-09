# The Export Render Path

**Preview** and **Export** run identical shaders. They differ in how much of the
frame is in flight at once: a Preview is one **Tile** that is the whole frame, an
Export is many Tiles of one frame. Everything else — the Passes, their order, the
Profile, the user's settings — is the same call.

That matters more than it sounds. A 48MP frame at the pipeline's RGBA float16 is
roughly 380MB *per intermediate texture*, and the graph holds around fourteen of them
at Tile size at once. Untiled, a 48MP Export asks for something over five gigabytes
and the OS kills the app. Tiled, the peak is the frame itself, the assembled output,
and one Tile's worth of intermediates.

## The Apron

Each Tile is rendered with an **Apron**: a margin that is rendered and then discarded
when the Tile's core is written out. Without it, a Halation halo crossing a Tile
boundary reads the edge of the Tile instead of the rest of the frame, and the result
is a **Tile Seam**.

The Apron is sized from the render Plan rather than from a constant, because what the
pipeline reaches for depends on the Stock, the user's controls *and* the frame: radii
are stored in **Film-Plane Microns** and become pixels through **Frame Width**, so the
same Stock reaches four times as far on a 48MP frame as on a 12MP one.

Three things reach:

| Pass | Reach |
| -- | -- |
| Bloom, Halation | the Scattering Pyramid's support, below |
| MTF | the coarse Gaussian's tap count, exactly |
| Geometry | the gate weave displacement plus one bilinear tap |

**The widest blur in the pipeline is Bloom, not Halation.** The modelled taking lens
diffuses over 900 µm against Cinestill 800T's 420 µm of halation, so at 48MP it is
Bloom asking for 200 pixels of sigma and Halation asking for 93. MEM-252 was written
before MEM-246 gave Bloom a Pass, and predicted Halation would dominate; it does not.

### Why the reach is not a multiple of sigma

Every blur in the pipeline is a *truncated* kernel — five texels either side at each
pyramid level — so unlike the Gaussian it approximates, the chain has **finite
support**. An Apron that wide makes a Tile exactly a window onto the untiled render
rather than approximately one, and the test asserts bit equality rather than a
tolerance.

Per axis, in level-zero pixels, when the coarsest weighted level is `L`:

* level 0's own blur reaches 5;
* each level after it reaches 10.5 of its own texels, through the blur and the 2×2
  average that fed it, which is `5.25 · 2^L` — and those sum geometrically;
* the bilinear step back down the levels adds one coarse texel each, `2^(L+1) − 2`.

Together, `12.5 · 2^L − 7.5`. That is around three and a half sigmas at the coarse
levels and nearer nine at the fine ones, which is exactly why a single sigma multiple
sized for one end of the pyramid under-provisions the other.

### The alignment nobody expects

An Apron alone is not enough. The Scattering Pyramid's 2×2 average pairs texels from
its texture's own origin, so two Tiles starting on different parities of that grid
halve the same halo differently and their shared boundary shows it. Tile origins are
therefore held to multiples of `2^L`.

For the same reason, `scatterUpsample` takes the coarse coordinate as an exact halving
of its own rather than as a ratio of the two textures' sizes. Those sizes round, and a
ratio drifts by a texel across a level whose dimensions are not a clean power of two:
invisible in a Preview, a seam in an Export.

### What it costs, and the knob that says so

Carrying the whole of that reach makes a 12MP Export about six times slower than
carrying half of it, because the Apron is paid on every side of every Tile.
`ExportOptions.apronFraction` names the trade. At the default of 0.6, on the
Catalogue's stress case — a point light ten stops over white through Cinestill 800T
at 200% halation — the tiled and untiled renders differ by four hundredths of an
eight-bit code value. Below about a half, the truncated tail starts to be a seam.

The memory budget caps the Apron independently. A Tile is core plus Apron whatever the
core is, so letting a very wide Apron shrink the core to compensate spends *more*
memory, on more Tiles, and quietly overruns the figure it was given. Where the widest
blur reaches further than the budget allows, `TilePlan.isApronCapped` says so.

## Grain in image-global coordinates

The Grain Pass is given the Tile's origin in the frame and adds it to the thread
position before addressing the noise lattice. Sampling in Tile-local coordinates would
restart the field at every Tile origin and print the same grain in every Tile — which
the tests catch as a spike in the field's autocorrelation at the Tile pitch.

In the shipped regime the grain is finer than a pixel, so the field is one independent
lattice sample per pixel and the tiled field is not merely similar to the untiled one:
it is the same field, pixel for pixel.

The Geometry Pass reads the same origin, and the whole frame's size with it: a vignette
is a fraction of the *frame's* diagonal and a frame border is the *frame's* edge.

## Progress, cancellation and thermals

Export runs on a command queue of its own, so a long render does not sit in front of
the Preview's next frame, and suspends between Tiles — which is where progress is
reported, where a cancellation lands, and where a hot device gets a gap worth having.
Nothing blocks the main actor: the renderer is an actor and the app awaits it.

When the thermal state reaches `.serious` the system is already throttling the GPU, so
asking for the expensive Grain Model there makes the Export both slower and hotter.
`Renderer.grainModel(_:path:thermalState:)` is the policy: the Preview always renders
`procedural`, an Export at rest renders the Stock's own model, and an Export under
thermal pressure falls back to `procedural`.

`dye-cloud` now has a kernel of its own, so an Export of a Stock that declares it —
Portra 400, Portra 160, Cinestill 800T and XP2 Super — differs from its Preview by
more than resolution. `stochastic`, silver halide as a Poisson point process
integrated per pixel, is still MEM-239's phase 7 and resolves to the procedural
kernel. See [the dye-cloud model](grain.md#the-dye-cloud-model).

## Writers

Display P3 by default, sRGB on request. Both share the sRGB transfer function and
differ only in primaries, and the Output Transform keeps values outside 0…1 rather
than clamping, so EDR headroom survives to the display; clipping to a format's range
is the writer's job.

HEIF and JPEG are written at eight bits per channel, TIFF at sixteen — the reason to
pick a TIFF is to keep more than a display can show, so an eight-bit one would defeat
the point. Every file is tagged with the colour space it was actually rendered in.
An untagged file is read as sRGB, which would silently undo a Display P3 export.

## The Exported LUT

`.cube` export falls out of MEM-239's tier split rather than being modelled
separately. Everything that is a pure per-pixel colour mapping — White Balance,
Exposure, the Film Response and its Development Offset blend, the Contrast Filter, the
Output Stage and the Output Transform — is exactly what a cube can carry, and
everything the runtime keeps for itself is exactly what it cannot. A Contrast Filter
qualifies because it resolves to a Monochrome Collapse weight rather than to a Pass;
the LUT's title names the glass so a folder of cubes stays legible.

So the LUT is *rendered*. The lattice is built as an image, run through the same Plan
and the same shaders as a photograph with the spatial Passes off, and read back.
Nothing reimplements the look, which is why it cannot drift from it, and the test
compares a cube entry against a 1×1 render of the same colour.

The lattice is addressed in the encoding the LUT returns — Display P3 in, Display P3
out — so it drops into a grade of already-display-encoded footage. `DOMAIN_MAX` is 1:
scene values above diffuse white are not addressable by a cube, and the app's own
render is where they still live.

**What it leaves out is Halation, Bloom, Grain, the Stock's MTF and the Geometry
Pass.** A LUT is a function of one pixel's colour and none of those five is. The file
header says so, and so does the export sheet, because a LUT that looks flatter than the
app gets reported as a bug otherwise.

## Measured

On an Apple Silicon Mac, release build, Cinestill 800T at default settings, from a
linear frame with a blown highlight:

| Frame | Apron | Tiles | Tile textures | Time |
| -- | -- | -- | -- | -- |
| 12MP | 476, as asked for | 6 × 5 | 299MB | 0.70 s |
| 48MP | 673, capped from 956 | 32 × 24 | 304MB | 13.0 s |

Against MEM-239's targets of under 2 s and under 15 s, with a 320MB budget for the Tile
textures. Both are met, the 48MP one narrowly and only because the Apron is capped:
without that cap the same frame takes 54 s and asks for 1.6GB. A phone will read
differently, and the number that actually matters there is that the Export finishes at
all. **On-device validation is still outstanding** — a simulator does not reproduce the
memory pressure any of this exists for.

## What the tests assert

`Tests/FilmEngineTests/ExportTests.swift`, through the renderer seam:

- A tiled Export of a frame is *identical* to the untiled render of it, with the full
  Apron, and within a code value at the default fraction.
- A `TilePlan`'s cores tile the frame exactly, every padded window lies inside it, and
  every Tile with room carries the full Apron.
- The Apron follows the widest blur and grows with the frame; a Profile with nothing
  spatial left needs none and exports as one Tile.
- A point light beside a Tile boundary leaves no step in the halo where it crosses.
- The Grain field does not repeat at the Tile pitch, by autocorrelation, and matches
  the untiled field pixel for pixel.
- Progress is monotone and per Tile; a cancelled Export throws rather than finishing.
- Every format round-trips through ImageIO at the right depth and tagged with the right
  colour space, and the Working Space is refused as a deliverable.
- sRGB and Display P3 agree on a neutral and disagree on a saturated red, in the
  direction the narrower gamut implies.
- An Exported LUT matches the in-app render with grain and halation at zero.
- The Grain Model policy degrades to `procedural` at `.serious` and above.
