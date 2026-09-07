# Renderer fixtures

`linear-low.dng` and `linear-high.dng` are synthetic 512×512 Bayer DNGs with a
known camera matrix and constant sensor values. The higher exposure is exactly
twice the lower. Regenerate them with `python3 Scripts/make-raw-fixtures.py`.
They contain no manufacturer data or third-party images. Apple RAW decoding needs
larger rasters than the tiny images used by the other tests.

`untagged.png` is a generated 480×320 RGB calibration raster without ICC, sRGB,
gamma or chromaticity chunks. It verifies that ImageIO's fallback sRGB colour
space is not silently accepted as an actual file tag.
