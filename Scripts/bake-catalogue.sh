#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product ProfileBaker
baker="$(swift build --show-bin-path)/ProfileBaker"
for stock in Curves/*; do
    # A directory with no stock.json is shared authoring input, such as the
    # Contrast Filters' transmittance table, rather than a Stock of its own.
    [ -f "$stock/stock.json" ] || continue
    "$baker" bake "$stock" "Sources/FilmEngine/Catalogue/$(basename "$stock").filmprofile"
done
