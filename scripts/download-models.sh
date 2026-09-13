#!/bin/bash
# Pagehum asset setup: pinned upstream files with SHA-256 verification.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
destination="${PAGEHUM_MODEL_DIR:-$repo/Resources}"
revision=9dcd3b06468a3c1ecee6d09a33ca687c8e708566
mkdir -p "$destination"
fetch() {
  local name="$1" expected="$2" base="$3" temporary
  if [ -f "$destination/$name" ] && [ "$(shasum -a 256 "$destination/$name" | awk '{print $1}')" = "$expected" ]; then
    printf 'Verified %s\n' "$name"
    return
  fi
  temporary="$(mktemp "$destination/.download.XXXXXX")"
  if ! curl --fail --location --retry 3 --output "$temporary" "$base/$revision/Resources/$name"; then
    rm -f "$temporary"
    return 1
  fi
  if [ "$(shasum -a 256 "$temporary" | awk '{print $1}')" != "$expected" ]; then
    printf 'Checksum mismatch for %s; existing file preserved.\n' "$name" >&2
    rm -f "$temporary"
    return 1
  fi
  mv "$temporary" "$destination/$name"
  printf 'Downloaded and verified %s\n' "$name"
}
fetch kokoro-v1_0.safetensors 4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8 https://media.githubusercontent.com/media/mlalma/KokoroTestApp
fetch voices.npz 56dbfa2f2970af2e395397020393d368c5f441d09b3de4e9b77f6222e790f10f https://raw.githubusercontent.com/mlalma/KokoroTestApp
