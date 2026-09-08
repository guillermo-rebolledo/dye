# The E-6 reversal branch

MEM-247 adds Provia 100F and Velvia 50, the first Stocks whose `process` is `e6`
and whose Profiles are baked rather than synthetic. Reversal film is the final
image, so its branch of the pipeline differs from a negative's in four places.

## `outputStage: none` skips inversion and print

`FilmProfile.validate` already required `outputStage: none` for E-6. The spectral
extension now accepts that alongside `scan`: a reversal Colour Cube is
`displayLinearRec2020` like a negative's, but what it carries is the transparency
itself rather than the Baker's scan of a negative. The renderer's Output Stage
resolves to `passthrough` for it, and setting `RenderSettings.outputStage` to
`scan` cannot put an inversion back. That is enforced on the Profile's own Output
Stage rather than on its cube's contents, so it holds for `study-e6` too, whose
Density Space cube the override could otherwise have inverted. Nothing in the
branch reaches the Print stage, which is still unimplemented for everything.

## The reversal density curve

The Characteristic Curves fall as exposure rises, so the spectral model checks
them for the opposite monotonicity and takes the Stock's minimum density from the
*last* plotted point rather than the first. Everything between — the spectral
reconstruction, the sensitivity integration, development contrast and shadow
loss, the DIR couplers — is the same model the negative Stocks use.

The output stage is not. In place of `SpectralModel.scan`, which removes the
Orange Mask, inverts in optical density and applies a scan gamma and shoulder,
`SpectralModel.transparency` reads the film the way a Viewing Light does: form the
spectral density from the base and the dyes, take its Beer–Lambert transmission,
integrate against the CIE observer under the viewing illuminant, and convert to
the Working Space. One per-channel scale puts the Curve Set's own reference
neutral on Working Space mid-grey; nothing else is balanced, because a
transparency has no auto-balance to emulate.

The result is **not clamped above one**. Clear film is brighter than mid-grey and
the Working Space carries that, exactly as it carries any other highlight;
clipping to a delivery range is the file writer's job, and a clamp in the Baker
would put a corner in the Colour Cube that the cube's own interpolation cannot
follow. Highlight clipping is therefore the film's, not the cube's: about five
stops fit between D-max and clear film, and above that the Stock has no density
left to lose and stops responding entirely, where a colour negative's twelve-plus
stops are still climbing. `reversalClipsHighlightsHarderThanColourNegativeAtMatchedExposure`
asserts exactly that difference.

## Dyes, and Velvia’s 65³ cubes

Fujifilm publishes the **isolated** cyan, magenta and yellow dye densities where
Kodak publishes an aggregate minimum and midscale neutral pair, so the reversal
branch consumes a `wavelengthNM,cyan,magenta,yellow` CSV and skips the artistic
Gaussian separation entirely. The charts are drawn peak-normalised, so they give
the dyes' shapes and not their amplitudes; rather than author three numbers, the
model solves for the amplitudes that reproduce the Curve Set's own measured
density above base at the reference neutral, read at each dye's own peak
wavelength where that dye dominates. Three equations from three measurements, and
no free parameter — what a Stock's saturation then comes from is its curve's
contrast and its DIR couplers, which is where it comes from on film.
Reversal film has no Orange Mask, so its base is modelled as spectrally flat at
the mean of the three measured minimum densities.

Velvia bakes 65³ Colour Cubes rather than 33³, and Provia does not. A reversal
curve turns much more sharply than a negative's, and Velvia's turns fastest: at
33 nodes the linear interpolation between them misses its D-max shoulder by
0.025 density against the Step Wedge's 0.03 bound, and a gate that is nearly
failing tells a reviewer nothing. 65³ takes that to 0.013 and Provia holds 0.016
at 33³. The extra nodes cost eight times the payload and eight times the bake, so
this is the Curve Set's own choice rather than a property of the branch; the cube
evaluation runs concurrently, which is what keeps the choice affordable at all.

## The Reciprocity Pass

Pass 4 was a placeholder until now. `FilmProfile.Reciprocity` carries three
Schwarzschild exponents, one per layer, and `RenderSettings.exposureSeconds` says
how long the frame was open. Below the Stock's `thresholdSeconds` the Pass
resolves to `passthrough` and twice the time is exactly twice the exposure; above
it each channel is scaled by `(seconds / thresholdSeconds)^(p − 1)` in linear
light, before Bloom, Halation and the Film Response, because reciprocity failure
is something the emulsion does to light on its way in.

Three exponents rather than one is the whole point: Velvia's published
compensation past one second is a magenta filter as well as an extra stop, which
says the green layer keeps more of its speed than red and blue, and the frame
shifts colour as it darkens. Both stocks' exponents are solved from the published
compensation tables — see each Curve Set's `SOURCES.md` for the arithmetic. A
Stock whose Curve Set records no failure has all three exponents at 1, the Pass
never runs for it, and the editor does not offer it an exposure-time control.

## What the editor shows

Controls that make no sense for the Process are hidden rather than disabled:

- The exposure-time slider appears only for a Stock with reciprocity failure, and
  its hint names which layer loses most once the frame is past the threshold.
- The third stage card offers no scan-or-print choice for a reversal Stock. It
  says the film is the final image and moves on to the Geometry controls, which
  belong to the frame and the lens rather than to the Process. There was no such
  toggle for any Stock before this, so what the card changes is what it *says*
  rather than a control it takes away.
- The development hint names the Box Speed when it differs from the True Speed the
  render meters at, so Velvia reading "EI 40" against a box that says 50 is
  visible rather than buried in the Curve Set.

## Metering at True Speed

`trueISO` had been carried in every Profile since the schema landed and read by
nothing. The Exposure Pass now rates each Stock at it: `log2(nominalISO / trueISO)`
stops on top of the user's own exposure, so Working Space mid-grey lands where a
meter set to the Stock's real speed would have put it rather than where the box
says. Every Stock in the Catalogue but two has the two speeds equal and is
unaffected; Velvia 50 gains a third of a stop and Cinestill 800T two thirds, the
latter because it is Vision3 500T's Emulsion sold faster than it behaves — back
the rating out and the two render the same frame, which is asserted.

The Step Wedge cancels the rating along with the push rating, because a wedge is
probed at the Curve Set's own physical log exposure and not at a metered one.
