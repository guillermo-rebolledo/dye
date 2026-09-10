# CineStill 800T process comparison: digitized manufacturer evidence

Retrieved 2026-09-10 from the official
[Cs2 product page, “Cs2 vs Cs41 Film Processing”](https://cinestill.film/products/cs2-cine-simplified-ecn-2-bath-kit-low-contrast-motion-picture-color-negatives-for-ecp-scanning).
This supplements the parent-derived stock data; these files alone do not create
an independently calibrated CineStill profile.

## Source and what is actually printed

The page embeds a
[four-panel sensitometric comparison JPEG](https://cdn.shopify.com/s/files/1/0339/5113/files/Sensitometric_Curves_Small_e6f46c28-1473-4348-9cd4-bde75bc1c745_2048x2048.jpg?v=1607588302).
Downloaded size: 1200 × 1200 pixels. SHA-256:
`d5bd88e6a12b4ca61d0aa03b4a86ab2562563e7167612d17ff160e9be1ac2456`.
Removing the Shopify resize suffix returns byte-identical image data.

The upper panels identify 800T, 3200 K tungsten exposure for 1/50 second,
process Cs41 or Cs2, and reference log H −1.535. Both plot red, green and blue
density from 0 to 3.5 against log exposure from −4 to +1. The bottom-right
panel overlays Cs2 on Kodak's curve chart and explicitly labels lux-seconds.
The upper panels do **not** state exposure units or densitometer status.

The product-page caption calls these 21-step sensitometric curves and identifies
Cs41, Cs2, their neutral comparison, and the Kodak comparison. The curves are
useful quantitative evidence of process-dependent shape; they are not an
unlabelled decorative illustration. [Manufacturer page](https://cinestill.film/products/cs2-cine-simplified-ecn-2-bath-kit-low-contrast-motion-picture-color-negatives-for-ecp-scanning).

## Extraction

Run with PyMuPDF 1.28.2 and NumPy:

```sh
python3 Scripts/digitize-cinestill-process.py manufacturer-graph.jpg output-directory
```

The script pins the image checksum, extracts the two upper colour-separated
panels and writes `process-cs41.csv` and `process-cs2.csv`, each with schema
`logExposure,red,green,blue`, 101 samples at 0.05 intervals. Values are absolute
plotted channel densities, not density above base. `logExposure` retains the
printed coordinate. Treating it as physical log10 lux-seconds is an inference
from the lower-right Kodak overlay, not a separately supplied calibration.

The calibrated frames are x = 86.0–563.5 and 665.5–1141.0 pixels, with
y = 57.0–541.5. Colour dominance separates the curves from grey axes/text;
explicit rectangles exclude the legends. Every sampled image column must have
one continuous coloured stroke. Its mean pixel-row position is the curve centre.
Linear interpolation produces the CSV grid. The obscured frame-edge columns
use the nearest visible centre, less than 0.02 log-exposure units away.

There is no fitted gamma, toe/shoulder extrapolation, black-level correction,
monotonicity enforcement or alignment to the existing Vision3 CSVs. Cs41's
almost flat toe contains a maximum adjacent decrease of 0.001535 density from
pixel quantization; a runtime monotonic response would require a separately
documented fit. The consuming model uses bounded cumulative-maximum
monotonization, allowing at most 0.01 density correction and rejecting a larger
reversal. That is a modelling treatment below the plotted stroke width, not a
change to these raw extracted CSVs. Sampling at 101 points does not turn a 21-step measurement into
101 independently measured exposures.

## Self-checks and uncertainty

Both source panels were inspected visually before extraction. Red, green and
blue assignments follow their printed legends. Repeating extraction at colour
dominance thresholds 45, 65 and 85 changes any sample by at most 0.003612
density. A one-pixel vertical displacement is 0.007224 density and a one-pixel
horizontal displacement approximately 0.0105 log exposure. The curves are
roughly four pixels thick, about 0.03 density vertically. These are extraction
uncertainty indicators, not specimen confidence intervals.

At plotted log exposure −1, the digitized R/G/B densities are:

| Process | Red | Green | Blue |
|---|---:|---:|---:|
| Cs41 | 1.368937 | 1.889061 | 2.156347 |
| Cs2 | 1.170279 | 1.657172 | 1.869556 |

These are readings of the pinned graph, not an independent laboratory check.
Six decimals preserve output reproducibility only.

## Limits before using this as stock calibration

No supplied raw measurements, error bars, batch identifier, exposure-device
calibration, densitometer spectral status or sample-specific development record
accompany the graph. The linked
[Cs2 kit instructions, revision 8/20](https://cdn.shopify.com/s/files/1/0339/5113/files/Cs2_powder_instructions.pdf?v=1606784127)
describe normal processing, but the page does not establish that the plotted
sample used those exact settings. Do not silently substitute generic kit
instructions for a missing experiment manifest.

These two tables support an explicitly approximate, manufacturer-chart-based
Cs41/Cs2 response comparison. They do not establish equivalent behaviour for
every C-41 lab, current emulsion batch, or controlled full ECN-2 process. They
also do not measure the C-41 dye/mask spectra, DIR, grain or halation. An
accurate full-colour CineStill model still requires a calibrated paired capture
or manufacturer clarification of the omitted conditions.

## Rights

Attribution: CineStill Film, for the product-page artwork the process curves were
digitised from, and Eastman Kodak Company for the curve chart one panel of that
artwork overlays.

**This is the weakest source in the repository and should be replaced.** The two
process curves were read from a marketing product page rather than from a technical
datasheet, and one panel is a third party's reproduction of another manufacturer's
chart, digitised at one further remove. No permission, licence or terms-of-use
statement covers either use, and none is claimed here.

What holds it up meanwhile is the same position as everywhere else in `Curves/`:
these are independent numerical readings, not the image, and nothing in `Curves/`
ships inside the application. That is a weaker argument here than elsewhere because
the source is not a publication of technical data.

**Replace or re-source** from a document CineStill publishes as technical data, or
drop the process-specific curves and mark the Profile's Provenance accordingly.
Tracked as REL-15 in `docs/audits/app-store-readiness.md`.
