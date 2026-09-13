#!/bin/sh
set -eu
bundle="$TARGET_BUILD_DIR/pagehum-resources.bundle/Contents"
mkdir -p "$bundle/Resources/ReaderScripts"
cp -p "$SRCROOT/Resources/kokoro-v1_0.safetensors" "$bundle/Resources/"
cp -p "$SRCROOT/Resources/voices.npz" "$bundle/Resources/"
cp -p "$SRCROOT"/Pagehum/ReaderScripts/* "$bundle/Resources/ReaderScripts/"
cat > "$bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.pagehum.cli.resources</string><key>CFBundlePackageType</key><string>BNDL</string></dict></plist>
PLIST
