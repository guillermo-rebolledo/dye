# The ECN-2 branch and the Print Output Stage

MEM-249 adds the four Kodak Vision3 motion picture stocks and makes the choice
between reading a negative by a scanner and reading it by an enlarger a real one.

## The four Vision3 stocks

`vision3-50d`, `vision3-250d`, `vision3-200t` and `vision3-500t` are the ECN-2
branch. 500T was already in the Catalogue as Cinestill 800T's parent Emulsion;
the other three are new Curve Sets from Kodak's own datasheets, and each one's
`SOURCES.md` records what came from which chart.

Two of them are daylight-balanced at 5500 K and two are tungsten at 3200 K, which
is the branch's most visible property. **A 5500 K scene through a 3200 K stock is
heavily blue, and that is correct.** The renderer does not auto-correct it,
because the film really was manufactured for a different light; White Balance is
where a photographer fixes it, and matching the Scene Illuminant to the Stock
Balance is an exact pass-through.
`tungstenStockRecordsDaylightAsBlueAndTheRendererDoesNotCorrectIt` asserts both
halves — the cast, and the fact that white balance removes it.

All four are **remjet**-backed, which is the one Halation number the branch
shares: `strength` 0.008 against Portra 400's 0.03, and 180/80/40 µm of
scattering against Portra's 220/90/45. Nobody publishes a figure for halation, so
these are artistic, but the *ordering* is not a guess — Kodak states the rem-jet
backing on page 1 of every one of these sheets, and Cinestill 800T is the same
Emulsion with the backing washed off at `strength` 0.55.
`remjetSuppressesHalationRelativeToStillNegative` asserts the ordering in the
Profiles and again in the halo the renderer actually draws.

250D is the one whose datasheet fought back. Kodak's current sheet for it is a
later edition that prints its charts as raster plates rather than vector paths,
and two of the four do not separate into curves reliably; that Curve Set's
[sources](../Curves/vision3-250d/SOURCES.md) records what was read from ink
pixels, what was borrowed from 50D instead, and what the borrowing costs.

## The Print is a second set of baked Colour Cubes

Everything an enlarger and a sheet of paper do to a negative is a spectral
integral over the negative's transmittance, so it is resolved where the scan's
is: in the Baker, once per Development Offset, into a Colour Cube. A Profile that
can print carries `colour.printVariants` alongside `colour.lutVariants` — the
same Development Offsets, its own payloads, and `displayLinearRec2020` output,
because a print is the final image the way a Transparency is.

The renderer's Output Stage therefore needs no new Pass and the Metal graph is
unchanged. `RenderSettings.outputStage` selects which set of cubes the Film
Response samples, and the Output Stage Pass resolves to a pass-through for both,
exactly as it already did for a spectral scan.

What it costs is payload: a printing Profile is twice the size, and takes twice
as long to bake. Both were judged worth it against the alternative, which was to
bake Density Space cubes and move the spectral scan into the shader, where a
spectral integral cannot go.

## The chain

`PrintModel` is the darkroom, and it reads the paper from
[one shared Curve Set](../Curves/ra4-paper/SOURCES.md) rather than from any
Stock, because a paper belongs to the darkroom — the same arrangement the
Contrast Filters' transmittance table has.

1. The negative's spectral transmittance, from the same dye amounts the scan
   reads: `10^-(Dmin(λ) + Σ dye(λ)·amount)`.
2. A 3200 K tungsten enlarger lamp through a dichroic **filter pack**, modelled
   as three subtractive filters shaped like the paper's own dyes.
3. Each of the paper's three layers integrates what reaches it against its
   published **spectral sensitivity**.
4. Each layer's published **characteristic curve** turns that exposure into
   density — the RA-4 paper density curve, and the reason a print is so much
   steeper than a scan.
5. Those densities are read as amounts of the paper's three dyes, and the print
   is read by reflection under the same Viewing Light a Transparency is.

Two things are solved rather than authored, and they are the two a printer sets.
The **filter pack** is solved so the Curve Set's own reference neutral lands on
the paper's aim, and the **exposure** is the pack's neutral-density part, split
out so the three filter densities sum to zero. Both are solved per Development
Offset, because a lab prints each roll to its own neutral — which is also what
the runtime scan's auto-balance does per variant.

The paper's aim is Kodak's Laboratory Aim Density, a neutral at 1.0. Which three
dye amounts *are* neutral at that density is solved rather than assumed: three
equal Status A densities are not a visual neutral, and a print balanced that way
would carry the difference to its paper white, where there is no dye left to hide
it.

## What the print looks like, and why it is not the default

A print is not a corrected scan. Against the same negative it is far steeper
through the midtones, closes the shadows several stops earlier, and ends at paper
white instead of rolling off. `printAndScanAreDifferentPicturesOfTheSameNegative`
asserts all three, plus the two things that make the toggle a fair comparison:
both stages put the Curve Set's reference neutral on Working Space mid-grey, and
a neutral prints neutral all the way up the scale.

Paper white lands about three stops above mid-grey, which is around 1.44 in the
Working Space. It is **not clamped**, for the reason a Transparency's clear film
is not: the Working Space carries highlights and clipping to a delivery range is
the file writer's job. A print has less headroom above display white than
reversal film does.

**Scan stays the default.** Most people's mental image of a film stock is a
Frontier or Noritsu scan, so a correct optical print reads as wrong the first
time it is seen. The editor therefore ships the choice as a segmented control at
the top of the third stage card rather than buried under the geometry sliders,
and the card's own description says what changed and why, but nothing selects
print for you. `printIsOfferedForColourNegativesOnlyAndScanIsWhatTheProfileAsksFor`
asserts that a render that says nothing about the Output Stage is the scan.

## Who gets the toggle

The control appears for a negative Stock whose Profile carries a Print, which is
every C-41 and ECN-2 Stock in the Catalogue except the two synthetic studies:
Portra 400, Portra 160, Cinestill 800T and the four Vision3 stocks.

- Reversal Stocks have no Output Stage at all. Asking one for a print cannot add
  one any more than asking it for a scan can, and both render the Transparency.
- Black & white Stocks have a Density Curve rather than a Colour Cube, and no
  spectral dye set for an enlarger to shine through.
- `study-c41` and `study-ecn2` are synthetic fixtures with no spectral model, so
  they have nothing to print from. Asking them for a print is an **error** rather
  than a silent fall back to their scan, which is what
  `askingAStockWithNoPrintForOneIsAnErrorRatherThanAScan` asserts. Changing the
  Stock in the editor clears a Print the new Stock cannot honour, in the canvas
  and in the thumbnail strip alike.

## Validation

`ProfileBaker validate` renders the print cubes through the public renderer entry
point at `outputStage: .print` and compares them against the model directly, as a
`print-output` stage in the same CSV and SVG report the `scan-output` stage
appears in. Its enlarger is filtered and exposed per Development Offset the way
the cube was baked, so a Profile baked against a different RA-4 paper fails there
rather than quietly rendering someone else's darkroom — the paper's three CSVs
are part of every printing Profile's source fingerprint.

## Density/observation separation

New bakes share one film-density transform between Scan and Print. A separate
Print observation cube per Development Offset reads the density after Grain.
The paper/enlarger model is unchanged, but grain no longer bypasses it. Generic
scanner and enlarger assumptions still require calibration against a chosen lab
workflow; see [accuracy validation](accuracy-validation.md).
