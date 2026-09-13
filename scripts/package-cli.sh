#!/bin/bash
# Package a previously built Pagehum CLI, including resources and notices.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
source="$repo/.build/pagehum-cli"
derived="${PAGEHUM_BUILD_DIR:-$repo/.build/pagehum}"
version="$("$source/pagehum" --version)"
case "$version" in *[!0-9A-Za-z.-]*|'') printf 'Invalid CLI version\n' >&2; exit 1;; esac
release="$repo/.build/releases"
staging="$(mktemp -d "$repo/.build/pagehum-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$release" "$staging/pagehum/licenses"
ditto "$source" "$staging/pagehum"
cp "$repo/LICENSE" "$repo/NOTICE" "$staging/pagehum/"
cp "$repo/docs/CLI.md" "$staging/pagehum/CLI.md"
cp "$repo/docs/RELEASE_NOTES.md" "$staging/pagehum/RELEASE_NOTES.md"
checkouts="$derived/SourcePackages/checkouts"
[ -d "$checkouts" ] || { printf 'Missing dependency sources for license notices\n' >&2; exit 1; }
while IFS= read -r -d '' license; do
  relative="${license#"$checkouts/"}"
  mkdir -p "$staging/pagehum/licenses/$(dirname "$relative")"
  cp "$license" "$staging/pagehum/licenses/$relative"
done < <(find "$checkouts" -type f \( -name 'LICENSE*' -o -name 'COPYING*' -o -name 'NOTICE*' \) -print0)
cat > "$staging/pagehum/START_HERE.txt" <<'TEXT'
Pagehum CLI — Your reading list, read aloud.

Apple Silicon, macOS 15.6 or later. This prerelease is not notarized.
From this extracted directory, run:
  ./pagehum --help
  ./pagehum voices
  ./pagehum generate --text "Your reading list, read aloud." -o hello.m4a

Keep this entire directory together: the bundles and frameworks are required.
The model and voice assets are included. URL input requires network access.
If your Mac blocks this unsigned prerelease, build from source instead:
https://github.com/Mieraidihaimu/pagehum

Source, setup, licenses, and limitations:
https://github.com/Mieraidihaimu/pagehum
TEXT
archive="pagehum-$version-macOS-arm64.tar.gz"
COPYFILE_DISABLE=1 tar -czf "$release/$archive" -C "$staging" pagehum
(cd "$release" && shasum -a 256 "$archive" > "$archive.sha256")
printf 'Packaged %s/%s\n' "$release" "$archive"
