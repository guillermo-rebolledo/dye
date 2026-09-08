# Contrast Filters

`transmittance.csv` is the shared spectral transmittance of the five Contrast
Filters, on the same 400…700 nm 10 nm grid every spectral table uses. It is not a
Curve Set: a filter is glass on the lens rather than a Stock, so it lives here
once and every monochrome Curve Set reads it. Directories with no `stock.json`
are skipped by `Scripts/bake-catalogue.sh` and by CI for that reason.

## What this file is

**It is a model, and it is artistic.** The Kodak Wratten transmittance
measurements are published in *Kodak Filters for Scientific and Technical Uses*
(publication B-3), which is a printed handbook and not a downloadable dataset,
so nothing here is digitised from a measurement the way the Stocks' Curve Sets
are. `Scripts/model-contrast-filters.py` emits five logistic band edges instead:

| Contrast Filter | Wratten | 50 % points (nm) | Peak transmittance |
| --- | --- | --- | --- |
| yellow | No. 8 | 495 … — | 0.87 |
| orange | No. 15 | 520 … — | 0.88 |
| red | No. 25 | 595 … — | 0.90 |
| green | No. 58 | 490 … 600 | 0.42 |
| blue | No. 47 | — … 495 | 0.28 |

Every edge is 7 nm wide. The wavelengths and peaks are the nominal values these
filters are described by; **no parameter is fitted** to anything in this
repository, which is what makes the check below worth running.

Wratten No. 15 is a deep yellow rather than a true orange. It is the Contrast
Filter named `orange` because it is the amber filter Kodak publishes a factor
for on both of these films, and because it does the job a photographer reaches
for an orange filter to do. Wratten No. 21 would be the literal orange and has
no published factor on either datasheet, so choosing it would have cost the
validation below for the sake of a name.

## What it is checked against

Both datasheets publish a daylight filter factor per Wratten filter, and the two
tables differ. A factor falls straight out of the derived Spectral Weights as
the ratio of their sums, so `ProfileBaker validate` reports one `filter-factor`
row per filter per Stock, in stops:

| Contrast Filter | Tri-X published / derived | T-Max published / derived |
| --- | --- | --- |
| yellow | 1.00 / 1.26 | 0.58 / 1.21 |
| orange | 1.32 / 1.47 | 1.00 / 1.45 |
| red | 3.00 / 3.01 | 3.00 / 3.04 |
| green | 2.58 / 2.68 | 2.58 / 2.60 |
| blue | 2.58 / 2.78 | 3.00 / 2.83 |

Red, green and blue agree to 0.19 stops against factors Kodak publishes rounded
to 1.5, 2, 2.5, 6 and 8 — a third of a stop of quantisation before the model is
even wrong. **Yellow and orange do not**: the model over-predicts what they cost
by 0.26 and 0.15 stops on Tri-X and by 0.63 and 0.45 stops on T-Max, and it
reproduces almost none of the difference Kodak publishes between the two Stocks
for those two filters. Both are minus-blue filters, so both residuals point at
the same place: the model's blue end, where the D65 surrogate for Kodak's
unspecified daylight, the reconstruction basis and each digitised sensitivity
curve's 400 nm endpoint all compound. It is a limitation of this file and of the
daylight assumption, not evidence about the digitised sensitivities.

The stage's bound is therefore **0.7 stops**, which is loose enough for yellow
on T-Max to pass and tight enough to catch a Contrast Filter applied as a tint,
dropped from the collapse, or read off the wrong Stock. It is deliberately not
the 0.03 the density stages answer to, and `StepWedgeStage.filterFactorStops`
says so where a reader will meet it.

What this check does establish is that the *sensitivities* are each Stock's own:
red and green agree on both films to within 0.1 stops using two independently
digitised curves and one shared transmittance table, so the agreement cannot be
coming from the filter model.

## Reproducing

```sh
python3 Scripts/model-contrast-filters.py Curves/contrast-filters
```

The script takes no inputs and depends on nothing. If a digitised Wratten
transmittance measurement ever becomes available, it replaces this file and the
residuals above are the thing to watch.
