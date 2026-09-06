#!/bin/bash
# Compose the shared Chorus mark, then package it at native macOS icon sizes.
#
# Chorus brand tokens: background #FBF4EA, ink #272F38, accent #EE9D00.
# ChorusSoundwave.png is the reusable source mark -- never extract it from a
# finished app icon. Provider identity is passed in as a label and is never
# baked into the shared mark.
set -euo pipefail
if [ "$#" -ne 2 ]; then
  echo "Usage: build-icon.sh <artifact-key> <provider-label>" >&2
  exit 1
fi

cd "$(dirname "$0")/../.."
artifact_key="$1"
provider_label="$2"
brand_out=".artifacts/$artifact_key/Brand"
appicon="$brand_out/AppIcon.xcassets/AppIcon.appiconset"
mkdir -p "$appicon" .build/module-cache
swift -module-cache-path .build/module-cache BuildSupport/Brand/main.swift \
  BuildSupport/Brand/ChorusSoundwave.png \
  "$brand_out/Chorus$artifact_key.png" \
  "#FBF4EA" \
  "#272F38" \
  "$provider_label"
cp BuildSupport/Brand/AppIconContents.json "$appicon/Contents.json"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$brand_out/Chorus$artifact_key.png" --out "$appicon/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$brand_out/Chorus$artifact_key.png" --out "$appicon/icon_${size}x${size}@2x.png" >/dev/null
done
