# Offline spectral model and the Portra gate

MEM-243 adds a 31-band, 400–700 nm model to the macOS Baker. Authoring supports
31–81 uniformly spaced bands if all three spectral CSVs share the same grid.
The five foundation studies retain their explicit independent-channel fixture
model. Portra uses `spectral.json`; malformed inputs never fall back to a study.
Vision3 500T uses the same model over its own digitised sources, and CineStill
800T is a derivation of Vision3 500T rather than a second run of the model —
see [the profile format](profile-format.md) for what a derivation may restate.

## Forward calculation

1. Reconstruct a nonnegative scene spectrum from linear Rec.2020 with a smooth
   three-lobe basis illuminated by D65. Integrate the basis with CIE 1931 2°
   functions and solve its 3×3 colourimetric transform. Normalize the truncated
   visible white to D65. Clamp negative reconstructed spectral power for highly
   saturated inputs outside this basis's spectral gamut. RGB cannot uniquely
   determine a spectrum: metamer choice and gamut projection are approximations.
2. Integrate scene spectral power against each measured layer sensitivity with
   trapezoidal endpoint weights. Calibrate neutral exposure against the same
   reference spectrum; the common wavelength interval cancels in normalization.
3. Interpolate the measured Characteristic Curves in physical log exposure.
   Development changes slope and shadow separation around the Curve Set's own
   reference gray — log H = −1.44 for Portra, −1.54 for Vision3 — not brightness.
   Portra's curves are Status M; Vision3's are Kodak's ECN-2 densitometry, read
   here as if they were Status M. A two-evaluation DIR model uses developed density in other layers
   to inhibit local exposure. Subtract the neutral-development contribution
   already present in the published curves, avoiding double-counting DIR.
4. Separate the measured aggregate midscale-minus-minimum absorption into three
   nonnegative dye lobes using artistic Gaussian weights. Scale their amplitudes
   with layer density above base, relative to midscale. This reproduces the
   aggregate measured absorption at the reference neutral. Status M layer density
   is an approximation to dye amount, not an isolated-dye measurement.
5. Form spectral density and apply Beer–Lambert transmission, `10^(−density)`.
   Integrate through three broad scanner channels under D65. Remove the measured
   minimum-density/Orange Mask transmission, invert in optical density, and
   auto-balance the reference gray. An artistic scan gamma and rational shoulder
   map the positive to display-linear values. Calibrate broad scanner channels
   back to Rec.2020 and clamp to the display interval. This is a generic scan,
   not a calibrated commercial scanner. There is no RA-4 print branch here.

## Colour Cube contract

Each spectral Stock's four 33³ RGBA float16 payloads represent offsets −1, 0, +1, +2, with
red changing fastest. RGB payload values are **display-linear Rec.2020**; alpha
is 1. `colour.cubeOutput = displayLinearRec2020` distinguishes them from the
foundation studies' Density Space cubes. Do not invert a scan cube again.

`colour.inputShaper` defines the normalized input coordinate:

```
logH = log10(max(sceneLinearRGB, epsilon) / 0.18) + middleGrayLogExposure
coordinate = clamp((logH - minimumLogExposure) / (maximumLogExposure - minimumLogExposure), 0, 1)
```

Portra's bounds are −3.5…0.6 lux-second log exposure with reference gray at −1.44,
roughly 13.6 stops; Vision3 500T's are −4.05…1.05 with reference gray at −1.54. The Baker evaluates physical exposure at those nodes. Below
and above that domain the renderer clamps to the endpoints. The renderer applies
this shaper itself whenever `colour.inputShaper` is present, after White Balance
and Exposure, so callers always supply scene-linear Working Space light. The
Development Offset blends the two nearest variants linearly and rates the Stock
faster by the same number of stops; the validation harness passes an equal
`exposureStops` so each variant is probed at the CSV's physical exposure.

## Validation

`ProfileBaker validate` emits CSV/SVG through the existing CLI seam:

- `measured-density`: offset 0, all digitised Characteristic Curve points and
  their midpoints. A diagnostic density cube runs through the public renderer
  and must match measured Status M density to 0.03. This gate is deliberately
  before scan inversion, because positive display RGB is not optical density.
- `scan-output`: all offsets, off-grid neutral and chromatic probes of the actual
  supplied Profile, fed as scene-linear light so the runtime shaper is exercised.
  Both stages render with the Scene Illuminant set to the Stock Balance, so White
  Balance passes through and a neutral probe stays neutral on a tungsten Stock, and
  with Halation off, because adjacent wedge samples are unrelated exposures.
  Compare the renderer to direct forward spectral evaluation
  to 0.03 in display-linear channel values. This bounds bake/interpolation error;
  it is **not** independent proof of the artistic colour or development model.

Before numerical checks, the CLI compares the Profile's SHA-256 source fingerprint
to the current Curve Set (including the spectral model version). This catches
changes to absolute density even if scan auto-balance would hide them. CI also
rebakes and checks exact Catalogue bytes. CLI tests exercise DIR ablation,
shape changes, malformed spectral tables, and source mismatch. Measured source
limitations and all tuning assumptions are documented in the Curve Set's
[SOURCES.md](../Curves/portra-400/SOURCES.md). Passing the numerical gate permits
MEM-244 work; it does not constitute a photographic colour match or measured RMS.
