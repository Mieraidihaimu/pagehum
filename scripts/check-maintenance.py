#!/usr/bin/env python3
"""Fast, offline repository checks. Requires Python 3.11+ and Bash; no Xcode or models."""
import json
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from xml.parsers.expat import ExpatError


ROOT = Path(__file__).resolve().parents[1]


def check_sources():
    errors = []
    checked = 0
    for path in sorted((ROOT / "scripts").rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT)
        try:
            if path.suffix == ".py":
                # Compile without executing smoke tests or leaving __pycache__ files.
                compile(path.read_bytes(), str(relative), "exec")
            elif path.suffix == ".sh":
                # Check POSIX build phases with sh, and Bash scripts with bash.
                shebang = path.read_text().partition("\n")[0]
                interpreter = "bash" if shebang in {"#!/bin/bash", "#!/usr/bin/env bash"} else "sh"
                result = subprocess.run(
                    [interpreter, "-n", str(path)], capture_output=True, text=True, check=False
                )
                if result.returncode:
                    errors.append(f"{relative}: {result.stderr.strip()}")
            else:
                continue
            checked += 1
        except (OSError, SyntaxError, ValueError) as error:
            errors.append(f"{relative}: {error}")
    return checked, errors


def check_metadata():
    errors = []
    checked = 0
    for directory in ("Pagehum", "PagehumShare", "Pagehum.xcodeproj/xcshareddata",
                      "Pagehum.xcodeproj/project.xcworkspace/xcshareddata"):
        for path in sorted((ROOT / directory).rglob("*")):
            if not path.is_file():
                continue
            try:
                if path.suffix in {".json", ".xcstrings", ".resolved"}:
                    json.loads(path.read_text())
                elif path.suffix in {".plist", ".entitlements", ".xcprivacy"}:
                    plistlib.loads(path.read_bytes())
                elif path.suffix == ".xcscheme":
                    ET.parse(path)
                else:
                    continue
                checked += 1
            except (OSError, ValueError, ET.ParseError, ExpatError, plistlib.InvalidFileException) as error:
                errors.append(f"{path.relative_to(ROOT)}: {error}")
    return checked, errors


def main():
    if sys.version_info < (3, 11):
        sys.exit("Maintenance checks require Python 3.11 or later.")
    sources, source_errors = check_sources()
    metadata, metadata_errors = check_metadata()
    errors = source_errors + metadata_errors
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print(f"Syntax checked {sources} scripts; validated {metadata} metadata files.", flush=True)
    result = subprocess.run(
        [sys.executable, "-B", "-m", "unittest", "discover", "-s", "scripts/tests", "-v"],
        cwd=ROOT, check=False,
    )
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
