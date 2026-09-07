#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product ProfileBaker
baker="$(swift build --show-bin-path)/ProfileBaker"
for stock in Curves/*; do
    [ -d "$stock" ] || continue
    "$baker" bake "$stock" "Sources/FilmEngine/Catalogue/$(basename "$stock").filmprofile"
done
