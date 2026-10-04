#!/usr/bin/env python3
"""Regression tests for packaging rejection, using synthetic bundles only."""
import importlib.util
import plistlib
import tempfile
import unittest
import datetime
from unittest.mock import patch
from pathlib import Path

spec = importlib.util.spec_from_file_location("release_validation", Path(__file__).with_name("validate-release.py"))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class ReleaseValidationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name) / "Synthetic.app"
        self.identifier = "org.example.Synthetic"
        self.group = "group.org.example.Shared"
        for name, point in [(None, None), ("CallDirectory", "com.apple.callkit.call-directory"),
                            ("MessageFilter", "com.apple.identitylookup.message-filter")]:
            bundle = self.app if name is None else self.app / "PlugIns" / (name + ".appex")
            bundle.mkdir(parents=True)
            info = {"CFBundleIdentifier": self.identifier + ("." + name if name else ""),
                    "SpamHoleContainingAppIdentifier": self.identifier,
                    "SpamHoleAppGroupIdentifier": self.group,
                    "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1",
                    "UIDeviceFamily": [1],
                    "CFBundleSupportedPlatforms": ["iPhoneOS"], "CFBundleExecutable": "Binary"}
            if name:
                info["NSExtension"] = {"NSExtensionPointIdentifier": point,
                                       "NSExtensionPrincipalClass": name + ".Handler"}
            else:
                info.update(CFBundlePackageType="APPL", UIDeviceFamily=[1],
                            NSContactsUsageDescription="Protect accessible contacts locally.",
                            BGTaskSchedulerPermittedIdentifiers=[self.identifier + ".refresh", self.identifier + ".processing"],
                            ITSAppUsesNonExemptEncryption=False, CFBundleIcons={"CFBundlePrimaryIcon": {}})
            self.write(bundle / "Info.plist", info)
            self.write(bundle / "PrivacyInfo.xcprivacy", {"NSPrivacyTracking": False,
                       "NSPrivacyTrackingDomains": [], "NSPrivacyCollectedDataTypes": [],
                       "NSPrivacyAccessedAPITypes": []})
            (bundle / "Binary").write_bytes(b"synthetic")

    def write(self, path, value):
        path.write_bytes(plistlib.dumps(value))

    def change_info(self, name, change):
        bundle = self.app if name is None else self.app / "PlugIns" / (name + ".appex")
        path = bundle / "Info.plist"
        info = plistlib.loads(path.read_bytes())
        change(info)
        self.write(path, info)

    def check(self):
        return validator.validate(self.app, check_binary=False)

    def testCustomIdentityConsistentAcrossBundles(self):
        self.assertEqual(self.check(), self.identifier)

    def testMismatchedExtensionGroupRejected(self):
        self.change_info("MessageFilter", lambda info: info.update(SpamHoleAppGroupIdentifier="group.org.example.Other"))
        with self.assertRaisesRegex(validator.ValidationError, "App Group configuration mismatch"):
            self.check()

    def testUnexpandedSettingRejected(self):
        self.change_info("CallDirectory", lambda info: info.update(CFBundleDisplayName="$(PRODUCT_NAME)"))
        with self.assertRaisesRegex(validator.ValidationError, "Unresolved"):
            self.check()

    def testMissingManifestRejected(self):
        (self.app / "PlugIns" / "MessageFilter.appex" / "PrivacyInfo.xcprivacy").unlink()
        with self.assertRaisesRegex(validator.ValidationError, "Cannot read PrivacyInfo"):
            self.check()

    def testNetworkSMSConfigurationRejected(self):
        self.change_info("MessageFilter", lambda info: info["NSExtension"].update(
            NSExtensionAttributes={"ILMessageFilterExtensionNetworkURL": "https://example.com/query"}))
        with self.assertRaisesRegex(validator.ValidationError, "network service"):
            self.check()

    def testVersionDriftRejected(self):
        self.change_info("CallDirectory", lambda info: info.update(CFBundleVersion="2"))
        with self.assertRaisesRegex(validator.ValidationError, "version mismatch"):
            self.check()

    def testSimulatorProductRejected(self):
        self.change_info(None, lambda info: info.update(CFBundleSupportedPlatforms=["iPhoneSimulator"]))
        with self.assertRaisesRegex(validator.ValidationError, "device build"):
            self.check()

    def testTrackingManifestRejected(self):
        path = self.app / "PrivacyInfo.xcprivacy"
        privacy = plistlib.loads(path.read_bytes())
        privacy["NSPrivacyTracking"] = True
        self.write(path, privacy)
        with self.assertRaisesRegex(validator.ValidationError, "Tracking"):
            self.check()

    def testExtensionFamilyDriftRejected(self):
        self.change_info("MessageFilter", lambda info: info.update(UIDeviceFamily=[2]))
        with self.assertRaisesRegex(validator.ValidationError, "iPhone only"):
            self.check()

    def testMalformedRequiredReasonDeclarationsRejected(self):
        path = self.app / "PrivacyInfo.xcprivacy"
        original = plistlib.loads(path.read_bytes())
        for api_type, reasons in [("", ["C617.1"]), ("NSPrivacyAccessedAPICategoryFileTimestamp", [123]),
                                  ("NSPrivacyAccessedAPICategoryFileTimestamp", [" "])]:
            with self.subTest(api_type=api_type, reasons=reasons):
                privacy = dict(original)
                privacy["NSPrivacyAccessedAPITypes"] = [{"NSPrivacyAccessedAPIType": api_type,
                                                        "NSPrivacyAccessedAPITypeReasons": reasons}]
                self.write(path, privacy)
                with self.assertRaisesRegex(validator.ValidationError, "required-reason"):
                    self.check()

    def testArm64SimulatorExecutableRejected(self):
        def tool(*args):
            return b"arm64\n" if "lipo" in args else b" platform IOSSIMULATOR\n"
        with patch.object(validator, "apple_tool", side_effect=tool):
            with self.assertRaisesRegex(validator.ValidationError, "Mach-O platform"):
                validator.validate(self.app)

    def testNonArm64ExecutableRejected(self):
        with patch.object(validator, "apple_tool", return_value=b"x86_64\n"):
            with self.assertRaisesRegex(validator.ValidationError, "device arm64"):
                validator.validate(self.app)

    def testDistributionProfileAndEntitlementChecks(self):
        # Synthetic tool results exercise validation logic; they do not prove actual signing.
        team = "SYNTHETIC1"
        signed = {"com.apple.security.application-groups": [self.group],
                  "com.apple.developer.team-identifier": team,
                  "application-identifier": team + "." + self.identifier, "get-task-allow": False}
        profile = {"ExpirationDate": datetime.datetime(2100, 1, 1), "TeamIdentifier": [team],
                   "Entitlements": {"application-identifier": team + "." + self.identifier,
                                    "com.apple.security.application-groups": [self.group], "get-task-allow": False}}
        (self.app / "embedded.mobileprovision").write_bytes(b"synthetic")
        cases = [
            ("valid", {}, {}, None),
            ("expired", {}, {"ExpirationDate": datetime.datetime(2000, 1, 1)}, "expired"),
            ("team", {"com.apple.developer.team-identifier": "OTHERTEAM1"}, {}, "teams differ"),
            ("group", {"com.apple.security.application-groups": ["group.org.example.Other"]}, {}, "Signed App Group"),
            ("debug", {"get-task-allow": True}, {}, "debug entitlements"),
            ("ad-hoc", {}, {"ProvisionedDevices": ["synthetic-device"]}, "ad hoc or enterprise"),
            ("enterprise", {}, {"ProvisionsAllDevices": True}, "ad hoc or enterprise"),
            ("profile-group", {}, {"Entitlements": dict(profile["Entitlements"], **{"com.apple.security.application-groups": []})}, "authorize App Group"),
        ]
        info = plistlib.loads((self.app / "Info.plist").read_bytes())
        for label, signed_changes, profile_changes, rejection in cases:
            with self.subTest(label=label):
                def tool(*args):
                    if args[0] == "security":
                        return plistlib.dumps(dict(profile, **profile_changes))
                    if "--entitlements" in args:
                        return plistlib.dumps(dict(signed, **signed_changes))
                    return b""
                with patch.object(validator, "apple_tool", side_effect=tool):
                    if rejection:
                        with self.assertRaisesRegex(validator.ValidationError, rejection):
                            validator.check_signature(self.app, info, self.group, team)
                    else:
                        self.assertEqual(validator.check_signature(self.app, info, self.group, team), team)


if __name__ == "__main__":
    unittest.main()
