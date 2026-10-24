#!/bin/bash
# Simulator regression tests followed by an unsigned device Release archive.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
derived="${PAGEHUM_BUILD_DIR:-$repo/.build/ios-verification}"
artifacts="${PAGEHUM_VERIFY_OUTPUT:-$repo/.build/ios-verification-results/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$artifacts"
if [ -z "${PAGEHUM_TEST_DESTINATION:-}" ]; then
  simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
sets = json.load(sys.stdin)["devices"]
phones = [d for runtime, devices in sets.items() if ".iOS-" in runtime for d in devices if d.get("isAvailable") and d["name"].startswith("iPhone")]
if not phones:
    sys.exit("Install an iPhone simulator runtime in Xcode before running verification.")
print(phones[0]["udid"])
')"
  destination="platform=iOS Simulator,id=$simulator_id"
else
  destination="$PAGEHUM_TEST_DESTINATION"
fi
common=(-project Pagehum.xcodeproj -scheme Pagehum-iOS -derivedDataPath "$derived"
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO)
xcodebuild "${common[@]}" -destination "$destination" -configuration Debug \
  ENABLE_DEBUG_DYLIB=NO -collect-test-diagnostics never \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -maximum-test-execution-time-allowance 120 \
  -resultBundlePath "$artifacts/Tests.xcresult" \
  'EXCLUDED_SOURCE_FILE_NAMES=kokoro-v1_0.safetensors voices.npz' test
xcodebuild "${common[@]}" -destination 'generic/platform=iOS' -configuration Release \
  -archivePath "$artifacts/Pagehum.xcarchive" archive
python3 scripts/verify-ios-archive.py "$artifacts/Pagehum.xcarchive"
printf '\nVerification artifacts: %s\n' "$artifacts"
