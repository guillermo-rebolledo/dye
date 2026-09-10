# dye

An iOS app that renders photographs through physically-motivated models of analog film stocks.

This file is the project's shared vocabulary. When the spec (MEM-239), an issue, a
commit message, a type name or a code comment names a domain concept, it uses the
term defined here. If you need a concept that isn't here, add it rather than
inventing a synonym in passing.

Several terms below exist specifically to break a collision — `balance`, `curve`,
`LUT`, `seam` and `development` each meant two or three different things across the
spec and the issues. Where a bare word is ambiguous it is listed under `_Avoid_`
and a qualified term is given instead.

## Shape of the model

A **Stock** is a real film product. Each Stock has exactly one **Profile**, the data
file that models it, and each Profile is baked from that Stock's **Curve Set** by the
**Baker**. A Profile may share Emulsion data with another Profile while retaining its own
Process response. CineStill 800T uses Vision3 500T as its Emulsion prior, but its
C-41 Characteristic Curves differ from the parent’s ECN-2 curves.

A Stock's **Process** decides which branch of the pipeline its image takes: colour
stocks resolve to a **Colour Cube**, black & white stocks to a **Monochrome Collapse**
followed by a **Density Curve**, and only negative stocks reach an **Output Stage**.

A render applies **Passes** in a fixed order to a photograph, in the **Working Space**.
The user's controls sit at specific points in that order — **Exposure** and
**White Balance** before the **Film Response**, **Development Offset** selecting
between Colour Cubes, **Bloom**, **Halation** and **Grain** scaled relative to the
Profile's own values, and the **Adjustments** over the scan after the **Output
Stage**. A **Preset** saves a Stock plus those settings.

## Language

### Film and stocks

**Stock**:
A real-world film product the app emulates, such as Portra 400.
_Avoid_: film, filmstock, emulsion (means something narrower)

**Process**:
The chemical development process a Stock belongs to — `c41`, `e6`, `bw-silver`,
`bw-chromogenic` or `ecn2`. Decides which branch of the pipeline an image takes.
_Avoid_: film type, category, family, chemistry

**Emulsion**:
The light-sensitive layer of a Stock. Shared Emulsion lineage does not imply the same developed response under different
Processes, as the CineStill 800T and Vision3 500T profiles illustrate.
_Avoid_: using it as a general synonym for Stock

**Stock Balance**:
The colour temperature in Kelvin a Stock is manufactured for — 5500K daylight or
3200K tungsten. A daylight scene through a tungsten Stock is correctly blue.
_Avoid_: balance (unqualified — collides with White Balance), colour temperature

**Box Speed**:
The ISO printed on the packaging.
_Avoid_: rated speed, nominal ISO, ISO (unqualified)

**True Speed**:
The ISO a Stock actually behaves at, which drives metering. Delta 3200 is nearer
1000; Fomapan 400 nearer 250.
_Avoid_: real ISO, effective speed, EI

**Latitude**:
The range of exposure across which a Stock records usable detail. Roughly 5 stops
for reversal, 12+ for colour negative, 13+ for ECN-2.

**Orange Mask**:
The integral colour-correction layer present in C-41 negative and absent from
reversal film.

**Remjet**:
The anti-halation backing on ECN-2 stocks. Its removal is what defines Cinestill 800T.

**DIR Coupler**:
Development-inhibitor-releasing compounds formed during development. The main source
of a Stock's characteristic colour, and the reason Characteristic Curves alone are
insufficient to model one.

**Reciprocity Failure**:
Loss of sensitivity at long exposure times, modelled by a Schwarzschild exponent
above a per-Stock threshold. One exponent per layer, not one per Stock: the three
lose speed at different rates, which is why a manufacturer's published
compensation is a colour-correction filter as well as an extra stop.

**Exposure Time**:
How long the frame was open, the user's control the Reciprocity Failure model
reads. It is not a second Exposure control and does nothing below the Stock's
threshold.
_Avoid_: shutter speed (the label, not the term), duration

### Profiles and data

**Profile**:
The data file modelling one Stock. One Stock has exactly one Profile; a Profile may
be derived from another rather than from its own Curve Set.
_Avoid_: preset (means a user artifact), LUT, config, definition

**Display Name**:
The user-facing name of a Stock, deliberately isolated as a single Profile field so
the whole Catalogue can be renamed for trademark reasons without touching anything else.
_Avoid_: title, label, name (unqualified — collides with the Profile's stable id)

**Catalogue**:
The full set of Profiles shipped in the app bundle.
_Avoid_: library (means the user's photo library), collection, pack

**Curve Set**:
The digitised datasheet CSVs for one Stock. Version-controlled and reviewed like
code; the project's actual source of truth.
_Avoid_: data, datasheet (means the published PDF), curves (unqualified)

**Characteristic Curve**:
The D-logE curve — density against log exposure — per channel for colour stocks.
_Avoid_: curve (unqualified), H&D curve, tone curve, response curve

**Colour Cube**:
A three-dimensional lookup describing either the Film Response in Density Space
or an observation of that density through a Scan, Print or Viewing Light.
_Avoid_: LUT (unqualified — collides with Exported LUT and Density Curve), 3D LUT, cube

**Density Curve**:
The 1024-entry one-dimensional lookup mapping collapsed grey to density for a black
& white Stock.
_Avoid_: 1D LUT, tone curve, transfer function

**Development Offset**:
Push or pull expressed in stops. Changes curve shape rather than brightness, so each
offset needs its own baked Colour Cube; the renderer blends the two nearest. As on a
pushed roll, the Stock is also rated faster by the same number of stops, which the
Exposure Pass applies as an EV offset.
_Avoid_: push, pull, development (unqualified — collides with the chemical process),
pushStops in prose

**Provenance**:
A per-parameter marker recording whether a value was measured from a datasheet,
tuned by eye, or is an **Approximation**. Halation strength is published by nobody
and is always tuned.

**Approximation**:
A parameter whose Stock publishes no usable measurement of it at all, so the value
stands in for one: a shape borrowed from a sibling Stock and adjusted, or a figure
read off reference scans. Distinct from a tuned value, which sits on top of the
Stock's own measured curves. A Profile carrying any Approximation is an
approximation, and the app labels it as one wherever it names the Stock.
_Avoid_: estimate, guess, empirical

**Bake**:
To run the spectral model over a Curve Set and emit a Profile.
_Avoid_: compile, generate, build, render

**Baker**:
The offline macOS command-line tool that bakes Profiles. Never ships inside the app.
_Avoid_: generator, compiler, toolchain

### The pipeline

**Pass**:
One stage of the thirteen-stage render pipeline. Their order is a correctness
requirement, not a performance preference.
_Avoid_: step, stage (collides with Output Stage), filter, node

**Working Space**:
Linear scene-referred float16 in a wide primary set. Every intermediate lives here;
no intermediate is ever 8-bit sRGB.
_Avoid_: colour space (unqualified), linear, scene-linear

**Exposure**:
The user's scalar multiply in linear light, applied before the Film Response. Models
choosing an exposure at the moment the frame was shot.
_Avoid_: brightness, gain, EV (keep for the unit)

**White Balance**:
The user's temperature and tint control, followed by chromatic adaptation from the
Scene Illuminant to the Stock Balance.
_Avoid_: balance (unqualified — collides with Stock Balance), WB, temperature

**Scene Illuminant**:
The light the frame was shot under, named by the White Balance control's
temperature and tint. Decoded photos already show grey as grey, so the renderer
re-illuminates the scene with it and adapts toward the Stock Balance. When the two
match, White Balance is an exact pass-through.
_Avoid_: source white, camera white balance, as-shot

**Halation**:
Light scattering off the back of the film and re-exposing the emulsion from behind.
Happens before the density curves, because it is an exposure phenomenon rather than
a post effect.
_Avoid_: glow, flare, bloom (a different phenomenon — see below)

**Bloom**:
Lens diffusion, as distinct from Halation: the taking lens spreading a fraction of
*all* the light across the frame, rather than the film reflecting light back into
itself. Has its own Profile parameters and its own Pass, both artistic. At 900
Film-Plane Microns it is the widest blur in the pipeline, so it is what sizes an
Export's Apron.
_Avoid_: using interchangeably with Halation

**Film Response**:
The Pass applying the Colour Cube, or for black & white the Monochrome Collapse
followed by the Density Curve.
_Avoid_: tone mapping, grading, the LUT pass, colour transform

**Monochrome Collapse**:
The integration of reconstructed scene light against a Stock’s sensitivity and
optional Contrast Filter, producing a single grey exposure.
_Avoid_: desaturation, greyscale conversion, luminance

**Spectral Weight**:
The per-Stock three-vector derived by integrating published spectral sensitivity
against CIE colour matching functions. Never a generic luminance weighting — that
substitution discards the entire point of the black & white branch. Derived by the
Baker rather than authored, like the source fingerprint.
_Avoid_: luma weights, channel mix, grey coefficients

**Contrast Filter**:
A spectral multiply applied before the Monochrome Collapse, modelling coloured glass
on the lens. Black & white only, and not a colour tint. Because the multiply is
inside the same integral the Spectral Weight comes from, it resolves at bake time to
one further Spectral Weight per filter rather than to a Pass of its own.
_Avoid_: filter (unqualified), tint, colour filter

**Filter Factor**:
What a Contrast Filter costs in light, published per Stock by the manufacturer and
recovered from the ratio of two Spectral Weights' sums. The renderer pays it, as a
photographer does, so fitting glass changes tonal separation and not exposure.
_Avoid_: exposure compensation, filter stops

**Density Space**:
The signal after the Film Response and before the Output Stage. Grain is applied
here so that the Output Stage acts on it the way it would on real film.
_Avoid_: log space, post-curve

**Grain Model**:
How a Stock's grain is generated — `procedural`, `dye-cloud` for chromogenic stocks,
or `stochastic`. Structurally different models, not parameter variations.
_Avoid_: noise, texture

**Density Response**:
The curve modulating grain amplitude by local density: loud in midtones, quiet in
deep shadow and blown highlight.

**RMS Granularity**:
The density fluctuation a Stock records through the standard 48 µm measuring
aperture. Selwyn's law converts that one published figure to any other aperture,
which is how it sets the Grain amplitude at every output resolution.
_Avoid_: noise level, grain amount, grain strength

**Film-Plane Micron**:
The unit every Halation and Grain radius is stored in, converted to pixels at render
time via Frame Width. Storing pixel values instead breaks resolution independence
irreparably.
_Avoid_: radius in pixels, size

**Frame Width**:
The physical width of a Stock's format — 36mm for 135 — used for the micron to pixel
conversion.

**Output Stage**:
What happens to a negative after the film: `scan`, `print`, or `none`. Reversal
stocks use `none`, because the film is already the final image.
_Avoid_: post, output, development (means Development Offset)

**Viewing Light**:
The illuminant and observer a Transparency is read by, standing where the Scan's
scanner stands for a negative. A standard viewer is a defined white, so it
cancels against the Curve Set's own reference neutral and what survives is the
dyes, not a white balance.
_Avoid_: light table, viewer, illuminant (unqualified — collides with Scene Illuminant)

**Scan**:
Scanner emulation — inversion plus auto-balance. The default for negative stocks,
because most people's mental image of a Stock is a scan rather than a print.
_Avoid_: Frontier, Noritsu, digitisation

**Print**:
Optical enlargement emulation — RA-4 paper density curve plus enlarger filtration.
_Avoid_: darkroom, paper, optical

**Paper**:
The RA-4 colour paper a Print is made on. It belongs to the darkroom rather than
to any Stock, so the Catalogue holds one shared Curve Set for it the way it holds
one shared Contrast Filter transmittance table.
_Avoid_: stock (means a film), print (means the result), substrate

**Filter Pack**:
The three subtractive dichroic densities in the enlarger head, solved so a Stock's
own reference neutral prints neutral. Its common part is neutral density, which is
an exposure time rather than a colour, so the pack's three components sum to zero
and the rest of it lives in the Print's exposure.
_Avoid_: filtration (unqualified), colour head, filters (collides with Contrast Filter)

**Transparency**:
The developed reversal image itself, read by transmission under a viewing light
rather than scanned or printed. A reversal Stock's Colour Cube carries one, which
is what makes its Output Stage `none` rather than merely unimplemented.
_Avoid_: slide, chrome, projection

**Adjustment Pass**:
The Pass applying the Adjustments to the positive the Output Stage returned — or
to the Transparency, or for the identity Profile to the Working Space itself. It
follows the Output Stage and precedes Geometry, because it is work done to the
scan afterwards and the Frame Border is not part of the scan. Per-pixel, so an
Exported LUT carries it. At neutral it does not run at all.
_Avoid_: grade, develop module, post, colour correction

**Adjustments**:
The user's tone and colour controls over the scan, the ones a photo editor offers:
Brilliance, Highlights, Shadows, Contrast, Brightness, Black Point, Saturation and
Vibrance. Bipolar, ±1 in the engine and ±100 in the app, with zero meaning not
applied. Exposure, Temperature and Tint are not Adjustments: they are the Light
controls and act before the film.
_Avoid_: edits, tweaks, sliders, corrections, develop settings

**Brilliance**:
An Adjustment that is not a curve of its own: the shadows opened, the highlights
pulled back and a little midtone contrast added, together. The renderer resolves
it to those three before the shader sees it.
_Avoid_: clarity, dehaze, pop

**Geometry**:
The Pass applying everything whose value depends on where in the frame a pixel
sits: the Vignette, the Gate Weave and the Frame Border. All three are the user's
controls rather than Profile parameters, and all three default to off.
_Avoid_: framing, transform, crop, geometry correction

**Vignette**:
Falloff toward the corners of the frame, following cos⁴ of the angle off axis.
A lens's own behaviour rather than a Stock's.
_Avoid_: edge darkening, corner falloff

**Gate Weave**:
The frame's displacement in the gate, in Film-Plane Microns. Fixed by the render's
Seed rather than animated: a still frame weaves once.
_Avoid_: jitter, shake, wobble

**Frame Border**:
The unexposed rebate around the exposed frame.
_Avoid_: sprocket holes, matte, letterbox

**Seed**:
The value fixing the Grain field and the Gate Weave displacement. The same Seed
renders the same frame, which is what makes Golden Images possible with Grain on.
_Avoid_: random seed, noise offset

### Rendering and output

**Render Path**:
Either Preview or Export. Both run identical shaders and differ only by a settings flag.
_Avoid_: mode, pipeline (means the Pass sequence)

**Preview**:
The screen-resolution Render Path, held whole in memory and re-rendered every frame
on parameter change.

**Export**:
The full-resolution tiled Render Path, never displayed live.

**Tile**:
One unit of work in the Export path.

**Apron**:
The margin around a Tile, sized to the largest blur radius in the pipeline, rendered
and then discarded on write-out. Exists to prevent Tile Seams.
_Avoid_: padding, border, overlap, margin

**Tile Seam**:
A visible discontinuity where an effect crosses a Tile boundary. Always a defect.
_Avoid_: seam (unqualified — collides with Test Seam)

**Exported LUT**:
A `.cube` file carrying the colour half of a look only, with no Halation and no Grain.
_Avoid_: LUT (unqualified), preset, look

**Preset**:
A user-saved combination of Stock and settings, reapplicable to other photographs.
_Avoid_: recipe, look, filter, style

### Validation

**Test Seam**:
A boundary in the codebase that tests assert across. The project deliberately has
three: the Profile codec, the renderer entry point, and the Baker CLI.
_Avoid_: seam (unqualified — collides with Tile Seam), boundary, interface

**Step Wedge**:
A synthetic linear ramp rendered through a Profile and compared numerically against
the Stock's Characteristic Curve. The primary Baker test.
_Avoid_: ramp, gradient, test chart

**Golden Image**:
A snapshot of a fixed render at fixed settings, which changes only by explicit update.
_Avoid_: baseline, reference image (collides with the Contact Sheet's input)

**Contact Sheet**:
One reference image rendered through the entire Catalogue at once, for perceptual
review after engine changes.
_Avoid_: grid, gallery, preview sheet

## Open questions

**Bloom's home is now the lens.** It was recorded here as having no Profile
parameter and no Pass. It now has both, on the reading that it is veiling glare in
the taking lens rather than anything the film does — which is why every Stock
carries the same modelled lens and both its parameters are artistic. If the
Catalogue ever wants to distinguish lenses, `bloom` is where that belongs, and it
should stop living in the Profile at that point. **Resolved, but note the seam.**

**"Approximation" is now a term.** It was open whether Foma and Kentmere would ship
labelled or be held back. They ship, labelled: `Provenance` has a third case and the
picker, the film subtitle and a line under the picker all say so. The decision was
forced by what the datasheets actually contain rather than by preference — Kentmere
publishes no characteristic curve and no spectral sensitivity at all, so its Profiles
borrow FP4 Plus's and HP5 Plus's shapes, while Foma's sheets turned out to publish
more than expected, including RMS granularity and a Schwarzschild table.
**Resolved.**
