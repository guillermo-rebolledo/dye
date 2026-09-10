# CineStill 800T Curve Set

This Profile shares Vision3 500T Emulsion data as a prior, but uses CineStill's
published **Cs41** process chart for its characteristic response. Shared lineage
does not imply identical response after different development.

## Characteristic response

`stock.json` names `process-cs41.csv` as `characteristicSource`. The Baker reads
its three channels instead of the parent's neutral curves. See
[PROCESS-SOURCES.md](PROCESS-SOURCES.md) for the manufacturer image URL, checksum,
extraction, uncertainty and process-specific limitations. The raw chart samples
are preserved. A cumulative maximum corrects only digitization reversals up to
0.01 density (actual Cs41 correction 0.001535); larger reversals fail baking.

The graph's physical exposure units are inferred from its Kodak overlay, not
explicitly specified on the Cs41 panel. That assumption is marked
`spectral.exposureUnits: approximation`. The parent's reference log exposure
−1.54 is within 0.005 of the manufacturer's displayed −1.535 reference. The graph
characterizes CineStill's kit and is not proof that all C-41 labs match it.

Box Speed and the default exposure rating are 800. The rating is an artistic
metering convention, not a measured sensitometric speed. EI 800 with normal C-41
processing is not itself a push; Development Offset remains a separate control.

## Shared and unmeasured parameters

The sensitivity and dye data, scanner, MTF, artistic development variants and
reciprocity model remain inherited priors. Borrowed sensitivity/dye/MTF inputs
carry approximation provenance. The parent's measured ECN-2 granularity curve is
**not** transferred to C-41: this Profile retains artistic grain parameters.

Halation strength 0.55, radii 420/150/70 µm, threshold 1.1 and tint 1/0.18/0.08
remain artistic. They represent removal of an anti-halation backing, not measured
halo profiles. Both stocks use a 3200 K Stock Balance; the white-balance transform
is still an RGB approximation to scene illumination.

Baking fingerprints the parent inputs, local process chart and override metadata.
Independent controlled C-41 captures and scans are still required to establish
photographic accuracy; the manufacturer graph alone does not calibrate the entire
finished look.

## Rights

Attribution: CineStill Film, for the published datasheets and technical publications cited
above. This repository contains **independent numerical readings and an extraction
script**, not the source PDFs and not reproduced chart artwork. Extracting numerical
facts from a published chart is a different act from reproducing the chart, and this
project keeps to the former.

**No open-content licence is claimed for CineStill Film's material.** Nothing in `Curves/`
ships inside the application; only the baked
`Sources/FilmEngine/Catalogue/*.filmprofile` files do. Dye is not affiliated with,
endorsed by, or sponsored by CineStill Film. See the repository's `NOTICE.md`.

CIE data in this directory is separately licensed CC BY-SA 4.0; see `NOTICE.md`.
