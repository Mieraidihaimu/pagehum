#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
derived="${PAGEHUM_BUILD_DIR:-$repo/.build/pagehum}"
configuration="${CONFIGURATION:-Release}"
xcodebuild -project "$repo/Pagehum.xcodeproj" -scheme pagehum \
  -configuration "$configuration" -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived" build CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
# Keep runtime bundles/frameworks beside the executable. SwiftPM's resource
# accessors and MLX's Metal library lookup need them after relocation.
products="$derived/Build/Products/$configuration"
package="$repo/.build/pagehum-cli"
mkdir -p "$package"
cp -p "$products/pagehum" "$package/"
for bundle in "$products"/*.bundle; do
  [ -d "$bundle" ] && ditto "$bundle" "$package/$(basename "$bundle")"
done
if [ -d "$products/PackageFrameworks" ]; then
  ditto "$products/PackageFrameworks" "$package/PackageFrameworks"
fi
printf '\nCLI ready: %s/pagehum\n' "$package"
