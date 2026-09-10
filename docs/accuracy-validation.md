# Film accuracy and validation

The engine separates three questions: whether the numerical implementation matches
its model, whether that model matches manufacturer measurements, and whether the
finished image matches a specified physical film/development/scan workflow. Passing
one does not establish the others.

## Changes following the September 2026 audit

- Colour middle gray is sampled through the actual log-exposure shaper. The old
  coordinate error suppressed grain at ordinary exposure.
- New spectral profiles contain a film-density transform followed by a separate
  scan, print or viewing transform. Grain acts on density before the observation.
  Preview and Export use the same grain algorithm, including under thermal load.
- Vision3 500T uses published individual dye/mask difference spectra, fitted to
  the aggregate neutral absorption. Its measured channel granularity curves apply
  over absolute density 0.95–2.00. Outside that range, endpoint holding is an
  approximation. Radii and spatial correlation still require physical calibration.
- CineStill uses the manufacturer's Cs41 characteristic chart rather than identical
  ECN-2 response cubes. The graph's exposure-unit inference and missing process
  details remain limitations; see its PROCESS-SOURCES.md. Normal EI 800 is no
  longer given the unsupported automatic 800/500 exposure adjustment.
- B&W Contrast Filters use official WRATTEN 2 density charts. Blocking regions
  clipped at density 3 are upper bounds on transmission, not measured zero.
  The maximum published-factor residual is about 0.60 stop; the 0.7-stop gate is
  unchanged. WRATTEN 2 charts do not eliminate uncertainty in older WRATTEN factors.
- B&W projects reconstructed spectral power to nonnegative values before collapse,
  matching the colour branch instead of extending negative spectra through a
  three-vector dot product. RGB reconstruction remains a metamer assumption.
- Published RGB MTF data are retained and fitted per channel. The two-Gaussian
  spatial approximation and the mapping to working RGB still need empirical checks.
- Borrowed Velvia dyes and Vision3 250D spectra now carry approximation provenance.

## Numerical checks

`ProfileBaker validate` still traverses the public renderer. It compares neutral
optical density to source characteristic curves and scan/print/viewing output to
direct spectral evaluation. Colour probes now include 129 neutrals, 512 Halton
samples across the cube and all eight corners. The absolute 0.03 gate is unchanged.

`ProfileBaker validate-model Curves/portra-400 <profile.filmprofile> <report.json>`
additionally compares the composed density/output cubes with the forward model,
including half-precision intermediate density and output. It needs no Metal
render but runs in the native macOS Baker. It reports scan and print separately.
It is a numerical interpolation test, never an independent film reference.

The denser coverage exposes errors that four chromatic probes missed. Cube
resolution is selected per source set against the same tolerance. Higher resolution
costs payload size and texture memory; observation and film-density payloads are
shared across variants/stages where the transform is identical.

The normal CI job enforces committed profile bytes and bit-exact golden images.
The optional **Film profile candidates** workflow is requested with the
`profile-candidates` PR label or manual dispatch. It produces native baked profiles
and rendered review candidates as artifacts; it neither commits them nor accepts
baselines. Review the contact sheets and numerical reports before copying accepted
artifacts into the repository, then run normal CI. Remove the PR label after review
to stop generating candidates on further pushes.

## Independent photographic benchmark

Run:

```sh
python3 Scripts/film_accuracy.py \
  Tests/FilmEngineTests/Fixtures/FilmReferences/manifest.json \
  /tmp/film-accuracy.json
```

The supplied manifest intentionally has no captures. The command fails with a clear
message until actual independent reference data are contributed. Synthetic unit
fixtures test the scorer and must never be presented as measured film accuracy.

A capture entry records:

```json
{
  "id": "capture-001",
  "stock": "portra-400",
  "batch": "record the film batch",
  "roll": "roll-001",
  "scene": "scene-001",
  "process": "record chemistry, time, temperature, agitation and lab",
  "illuminant": "record source and measured spectrum when available",
  "exposure": "record EI, aperture, time and measured illumination",
  "scanner": "record hardware, software and all fixed settings",
  "inputKind": "scene-linear-raw",
  "split": "validation",
  "metric": "deltaE00",
  "reference": {"path": "reference.csv", "sha256": "actual file SHA-256"},
  "candidate": {"path": "candidate.csv", "sha256": "actual file SHA-256"}
}
```

The paths are relative to the manifest directory. Colour CSVs use
`sample,L,a,b`; density CSVs use `sample,red,green,blue`. Density entries use
`metric: density` and also record `densityStatus` and `measurementGeometry`.
Samples must match exactly, files must match their hashes, and neither rolls nor
scenes may span calibration and validation. There must be a held-out roll. The
manifest records input/output transforms, reference white and usage rights.

Report colour and density in their own units. CIEDE2000 uses kL=kC=kH=1; its tests
include published Sharma/Wu/Dalal reference pairs. Reports include median, nearest-
rank 95th percentile, maximum and individual sample errors. Acceptance limits must
come from reference repeatability; the scorer does not invent an accuracy score or
silently accept every report. Use a fixed RGB-to-Lab transform and patch interiors
for both images. Separately measure grain PSD/covariance, MTF, and halation profiles
following the audit's capture protocol.

## What still needs external measurements

- Paired RAW and film captures under controlled illumination, repeat rolls and
  repeated scans. No photographic accuracy improvement has been quantitatively
  established from real film by this change alone.
- A specified scanner/inversion pipeline; the current broad scanner channels and
  scan gamma are generic. Linearizing a JPEG does not recover unknown camera
  rendering or clipped scene exposure. Benchmark rendered inputs separately.
- Appropriate densitometer weighting functions and geometry for dye-amount fitting.
  Reversal Status A density is not a dye-peak amplitude. ECN-2 names a process,
  not a new density status; no speculative conversion is introduced.
- Illumination spectra and target reflectances for spectral reconstruction and
  viewing-light calibration. Neutral normalization does not cancel illuminant
  effects on every coloured dye mixture.
- Process-specific push/pull curves, long-exposure corrections beyond published
  ranges, grain radii/covariance, and measured lens/halation profiles. Existing
  artistic controls remain artistic; their presence is not evidence of calibration.

These limits are recorded rather than filled with invented measurements. The
[audit](audits/film-stock-accuracy.md) describes the original baseline, and the
[primary-source research](audits/film-stock-accuracy-research.md) links the evidence.
