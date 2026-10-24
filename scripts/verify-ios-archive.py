#!/usr/bin/env python3
"""Validate an unsigned or signed iPhone archive before distribution signing."""
import plistlib
import sys
from pathlib import Path


def read_plist(path):
    with path.open('rb') as source:
        return plistlib.load(source)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(archive):
    app = archive / 'Products/Applications/Pagehum.app'
    extension = app / 'PlugIns/PagehumShare.appex'
    main = read_plist(app / 'Info.plist')
    share = read_plist(extension / 'Info.plist')
    require(main['CFBundleSupportedPlatforms'] == ['iPhoneOS'], 'Archive must target physical iOS devices')
    require(main['MinimumOSVersion'] == share['MinimumOSVersion'], 'App and share extension minimum iOS versions differ')
    require(share['CFBundleIdentifier'].startswith(main['CFBundleIdentifier'] + '.'), 'Extension bundle identifier must be a child of the app identifier')
    for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
        require(main[key] == share[key], f'App and extension {key} differ')
    require(main.get('UIBackgroundModes') == ['audio'], 'Only the implemented audio background mode is allowed')
    for bundle, expected in ((app, {'UserDefaults': {'CA92.1', '1C8F.1'}, 'FileTimestamp': {'C617.1'}}),
                             (extension, {'UserDefaults': {'1C8F.1'}})):
        privacy = read_plist(bundle / 'PrivacyInfo.xcprivacy')
        require(privacy.get('NSPrivacyTracking') is False, f'{bundle.name} declares tracking')
        entries = {e['NSPrivacyAccessedAPIType']: set(e['NSPrivacyAccessedAPITypeReasons'])
                   for e in privacy['NSPrivacyAccessedAPITypes']}
        for category, reasons in expected.items():
            require(reasons <= entries.get('NSPrivacyAccessedAPICategory' + category, set()),
                    f'{bundle.name} is missing {category} privacy reasons')
    for name in ('kokoro-v1_0.safetensors', 'voices.npz'):
        require(not list(app.rglob(name)), f'Release archive unexpectedly bundles {name}')
    require((app / main['CFBundleExecutable']).is_file(), 'Main executable is missing')
    require((extension / share['CFBundleExecutable']).is_file(), 'Share extension executable is missing')
    print(f'iPhone archive checks passed: {archive}')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('Usage: verify-ios-archive.py PATH.xcarchive')
    try:
        verify(Path(sys.argv[1]))
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException) as error:
        sys.exit(f'Archive verification failed: {error}')
