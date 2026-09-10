# Contrast Filters

`transmittance.csv` contains shared spectral transmittance for five Kodak
WRATTEN 2 filters at 400–700 nm in 10 nm increments. It replaces the previous
artistic logistic-edge table. This directory is not a stock Curve Set.

## Primary sources

Retrieved 2026-09-10 through Kodak's official
[WRATTEN 2 filter catalogue](https://www.kodak.com/en/motion/page/wratten-2-filters/).
Each link below is a one-page manufacturer PDF of typical production diffuse
density versus wavelength, not a measurement of the particular filter a user
owns. Kodak cautions that the published curves are not production acceptance
specifications.

| Application name | Kodak filter and source | SHA-256 |
|---|---|---|
| yellow | [WRATTEN 2 No. 8](https://www.kodak.com/content/products-brochures/Film/Basic-Color-Filters-w2-8.pdf) | `5975c86498145713c0a864a9c3303f8f3522140856df3a14456fe43b2b00c4d0` |
| orange | [WRATTEN 2 No. 15](https://www.kodak.com/content/products-brochures/Film/Basic-Color-Filters-W2-15.pdf) | `acbffbc45ce201913229fec81f3bc516b0587fe2a4b42142be01a3fcfae70a1e` |
| red | [WRATTEN 2 No. 25](https://www.kodak.com/content/products-brochures/Film/Basic-Color-Filters-W2-25.pdf) | `a7f209922fce39413a1632a53952c9c0c5dc10a4e22103812d4a272d661234bb` |
| green | [WRATTEN 2 No. 58](https://www.kodak.com/content/products-brochures/Film/Basic-Color-Filters-W2-58.pdf) | `a2305795138fe68adac82b963b90a62b3272674bb4f5f208a6207e8b74e82beb` |
| blue | [WRATTEN 2 No. 47](https://www.kodak.com/content/products-brochures/Film/Basic-Color-Filters-W2-47.pdf) | `168a816b10cf0b56ac4c0aaba50a39206c0c78e1c79f802adaa3f5bb21a02bba` |

No. 15 is deep yellow, despite the application's `orange` name. It remains
No. 15 because the film reference tables specify that filter. Attribution:
Eastman Kodak Company, KODAK WRATTEN 2 Optical Filter curves. The repository
contains independent numerical readings and an extraction script, not the
source PDFs or reproduced chart artwork. No open-content licence is claimed
for Kodak's material; [Kodak's terms](https://www.kodak.com/en/company/page/site-terms/)
describe its permitted research and product-information uses.

## Extraction and censored values

`Scripts/digitize-wratten.py` pins every PDF checksum and uses PyMuPDF 1.28.2
to read vector paths. Four pages are rotated 90 degrees; coordinates are
transformed by the page rotation matrix before axis calibration. Each page's
own frame defines 300–900 nm and density 0–3. Straight segments are used
directly; No. 15's cubic segments are sampled at 101 points. Interpolation is
in density, followed by `T = 10^(-D)`. The passbands retain their measured
attenuation; they are not normalized to unit transmission.

Disconnected curve groups remain separate. The omitted blocking sections and
any paths above the visible density-3 limit are **censored measurements**:
they establish transmission at most 0.001. The CSV uses that upper bound as an
explicit conservative approximation, not a measured zero or measured exact
0.001. It does not interpolate across missing chart sections.

| Filter | Censored sample wavelengths, inclusive, 10 nm spacing |
|---|---|
| yellow | 400–450 nm |
| orange | 400–500 nm |
| red | 400–570 nm |
| green | 400–460 nm; 620–700 nm |
| blue | 540–680 nm |

The printed stroke is about 1.92 PDF points, approximately 0.015 density or
3.6% transmission for a full stroke width. This is a reading-resolution
indicator, not a confidence interval. Six CSV decimals preserve reproducibility,
not measurement precision. UV/IR transmission outside 400–700 nm is excluded
from the model even where the original chart shows it.

## Independent filter-factor check

The following direct spectral calculation uses each stock's digitized
`sensitivity.csv`, its D65 `observer.csv`, trapezoidal endpoint weights, and
the six-decimal emitted transmittance table:

```text
filterFactorStops = log2(sum(sensitivity * D65 * quadrature)
                        / sum(sensitivity * D65 * T * quadrature))
```

It does not fit the curves to the published factors. Compared with each
stock's transcribed Kodak daylight `filter-factors.csv`:

| Filter | Tri-X published / computed stops | T-Max published / computed stops |
|---|---:|---:|
| yellow | 1.000000 / 1.190282 | 0.584963 / 1.148225 |
| orange | 1.321928 / 1.490573 | 1.000000 / 1.478598 |
| red | 3.000000 / 2.987646 | 3.000000 / 3.001455 |
| green | 2.584963 / 3.183390 | 2.584963 / 3.058930 |
| blue | 2.584963 / 2.377920 | 3.000000 / 2.459078 |

Maximum absolute residual is **0.598427 stops**, Tri-X green. All ten remain
inside the existing **0.7-stop** validation bound; that bound is not enlarged.
The former claim of green agreement within 0.1 stops described the old artistic
filter table and does not survive measured transmission. Its failure must not
be hidden by tuning the new source curves. Red still agrees within 0.02 stops.

These residuals include the unspecified daylight spectrum replaced by D65,
400 nm sensitivity truncation, digitization, and differences between the
manufacturer's filter/film test conditions and this model. Kodak says WRATTEN 2
has the same spectral response as its gelatin predecessor, but the older film
filter factors do not establish same-batch or same-instrument equivalence to
these particular WRATTEN 2 curves. Do not attribute all residuals to any one
cause without additional measurements.

Setting only the censored entries to zero for a sensitivity analysis changes
the computed factors by less than 0.010 stops for these two stocks. Thus the
blocking-floor approximation does not account for the larger remaining errors.

## Reproducing

Download the five source PDFs into a temporary directory, naming them
`w2-8.pdf`, `W2-15.pdf`, `W2-25.pdf`, `W2-58.pdf`, and `W2-47.pdf`, then run:

```sh
python3 Scripts/digitize-wratten.py pdf-directory Curves/contrast-filters
```

The script reports every censored wavelength. The legacy
`Scripts/model-contrast-filters.py` recreates the superseded artistic table;
it is not the generator of this measured source table.
