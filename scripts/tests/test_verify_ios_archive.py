"""Exercise release packaging gates with tiny archives, without Xcode or voice weights."""
import contextlib
import importlib.util
import io
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


VERIFIER = Path(__file__).resolve().parents[1] / "verify-ios-archive.py"
spec = importlib.util.spec_from_file_location("verify_ios_archive", VERIFIER)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class ArchiveVerificationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="pagehum-archive-test-")
        self.addCleanup(temporary.cleanup)
        self.archive = Path(temporary.name) / "Pagehum.xcarchive"
        self.app = self.archive / "Products/Applications/Pagehum.app"
        self.extension = self.app / "PlugIns/PagehumShare.appex"
        self.extension.mkdir(parents=True)
        self.write_plist(self.app / "Info.plist", {
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "MinimumOSVersion": "18.6",
            "CFBundleIdentifier": "com.example.pagehum",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "CFBundleExecutable": "Pagehum",
            "UIBackgroundModes": ["audio"],
        })
        self.write_plist(self.extension / "Info.plist", {
            "MinimumOSVersion": "18.6",
            "CFBundleIdentifier": "com.example.pagehum.share",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "CFBundleExecutable": "PagehumShare",
        })
        for bundle, reasons in (
            (self.app, {"UserDefaults": ["CA92.1", "1C8F.1"], "FileTimestamp": ["C617.1"]}),
            (self.extension, {"UserDefaults": ["1C8F.1"]}),
        ):
            self.write_plist(bundle / "PrivacyInfo.xcprivacy", {
                "NSPrivacyTracking": False,
                "NSPrivacyAccessedAPITypes": [
                    {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategory" + category,
                     "NSPrivacyAccessedAPITypeReasons": values}
                    for category, values in reasons.items()
                ],
            })
        (self.app / "Pagehum").touch()
        (self.extension / "PagehumShare").touch()

    @staticmethod
    def write_plist(path, contents):
        path.write_bytes(plistlib.dumps(contents))

    def update_plist(self, path, **changes):
        contents = plistlib.loads(path.read_bytes())
        contents.update(changes)
        self.write_plist(path, contents)

    def verify(self):
        with contextlib.redirect_stdout(io.StringIO()):
            verifier.verify(self.archive)

    def run_cli(self, *args):
        return subprocess.run(
            [sys.executable, "-B", str(VERIFIER), *map(str, args)],
            capture_output=True, text=True, check=False, timeout=10,
        )

    def test_accepts_unsigned_device_archive(self):
        self.verify()
        result = self.run_cli(self.archive)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("iPhone archive checks passed", result.stdout)

    def test_rejects_simulator_archive(self):
        self.update_plist(self.app / "Info.plist", CFBundleSupportedPlatforms=["iPhoneSimulator"])
        with self.assertRaisesRegex(ValueError, "physical iOS devices"):
            self.verify()

    def test_rejects_mismatched_deployment_versions(self):
        self.update_plist(self.extension / "Info.plist", MinimumOSVersion="19.0")
        with self.assertRaisesRegex(ValueError, "minimum iOS versions differ"):
            self.verify()

    def test_rejects_unrelated_extension_identifier(self):
        self.update_plist(self.extension / "Info.plist", CFBundleIdentifier="com.example.pagehumOther.share")
        with self.assertRaisesRegex(ValueError, "child of the app identifier"):
            self.verify()

    def test_rejects_mismatched_marketing_and_build_versions(self):
        path = self.extension / "Info.plist"
        original = path.read_bytes()
        for key in ("CFBundleShortVersionString", "CFBundleVersion"):
            with self.subTest(key=key):
                path.write_bytes(original)
                self.update_plist(path, **{key: "2"})
                with self.assertRaisesRegex(ValueError, key + " differ"):
                    self.verify()

    def test_requires_only_audio_background_mode(self):
        for modes in ([], ["fetch"], ["audio", "processing"]):
            with self.subTest(modes=modes):
                self.update_plist(self.app / "Info.plist", UIBackgroundModes=modes)
                with self.assertRaisesRegex(ValueError, "audio background mode"):
                    self.verify()

    def test_rejects_tracking_in_app_and_extension(self):
        for bundle in (self.app, self.extension):
            with self.subTest(bundle=bundle.name):
                path = bundle / "PrivacyInfo.xcprivacy"
                original = path.read_bytes()
                self.update_plist(path, NSPrivacyTracking=True)
                with self.assertRaisesRegex(ValueError, bundle.name + " declares tracking"):
                    self.verify()
                path.write_bytes(original)

    def test_requires_every_privacy_reason(self):
        for bundle in (self.app, self.extension):
            path = bundle / "PrivacyInfo.xcprivacy"
            original = path.read_bytes()
            privacy = plistlib.loads(original)
            for entry in privacy["NSPrivacyAccessedAPITypes"]:
                for reason in list(entry["NSPrivacyAccessedAPITypeReasons"]):
                    with self.subTest(bundle=bundle.name, reason=reason):
                        entry["NSPrivacyAccessedAPITypeReasons"].remove(reason)
                        self.write_plist(path, privacy)
                        with self.assertRaisesRegex(ValueError, "missing .* privacy reasons"):
                            self.verify()
                        entry["NSPrivacyAccessedAPITypeReasons"].append(reason)
                        path.write_bytes(original)

    def test_accepts_additional_privacy_categories(self):
        path = self.app / "PrivacyInfo.xcprivacy"
        privacy = plistlib.loads(path.read_bytes())
        privacy["NSPrivacyAccessedAPITypes"].append({
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryDiskSpace",
            "NSPrivacyAccessedAPITypeReasons": ["E174.1"],
        })
        self.write_plist(path, privacy)
        self.verify()

    def test_rejects_voice_weights_even_in_nested_bundles(self):
        resources = self.app / "Frameworks/Dependency.bundle/Resources"
        resources.mkdir(parents=True)
        for name in ("kokoro-v1_0.safetensors", "voices.npz"):
            with self.subTest(name=name):
                asset = resources / name
                asset.touch()
                with self.assertRaisesRegex(ValueError, "unexpectedly bundles " + name):
                    self.verify()
                asset.unlink()

    def test_requires_app_and_extension_executables(self):
        for binary in (self.app / "Pagehum", self.extension / "PagehumShare"):
            with self.subTest(binary=binary.name):
                binary.unlink()
                with self.assertRaisesRegex(ValueError, "executable is missing"):
                    self.verify()
                binary.touch()

    def test_cli_rejects_missing_archive(self):
        result = self.run_cli(self.archive / "missing")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Archive verification failed:", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_cli_rejects_invalid_plist(self):
        (self.app / "Info.plist").write_bytes(b"invalid plist")
        result = self.run_cli(self.archive)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Archive verification failed:", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_cli_rejects_truncated_xml_plist(self):
        (self.app / "Info.plist").write_bytes(b'<?xml version="1.0"?><plist><dict>')
        result = self.run_cli(self.archive)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Archive verification failed:", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_cli_requires_archive_argument(self):
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Usage:", result.stderr)


if __name__ == "__main__":
    unittest.main()
