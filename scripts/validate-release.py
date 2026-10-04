#!/usr/bin/env python3
"""Validate built SpamHole bundles; signed mode additionally checks profiles.

An unsigned pass proves packaging consistency only, never device acceptance or
App Store eligibility. Uses only the Python standard library and Apple tools.
"""
import argparse
import datetime
import fnmatch
import plistlib
import re
import subprocess
from pathlib import Path


class ValidationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def read_plist(path):
    try:
        with path.open("rb") as stream:
            value = plistlib.load(stream)
        require(isinstance(value, dict), f"{path.name}: expected a dictionary")
        return value
    except (OSError, plistlib.InvalidFileException, ValueError) as error:
        raise ValidationError(f"Cannot read {path.name}: {error}") from error


def resolved(value):
    if isinstance(value, str):
        require("$(" not in value and "${" not in value,
                "Unresolved build setting in built Info.plist")
    elif isinstance(value, dict):
        for item in value.values():
            resolved(item)
    elif isinstance(value, list):
        for item in value:
            resolved(item)


def check_privacy(bundle):
    privacy = read_plist(bundle / "PrivacyInfo.xcprivacy")
    require(privacy.get("NSPrivacyTracking") is False, "Tracking must be disabled")
    require(privacy.get("NSPrivacyTrackingDomains") == [], "Tracking domains must be empty")
    require(privacy.get("NSPrivacyCollectedDataTypes") == [],
            "New data collection requires reviewed policy and App Store answers")
    api_types = privacy.get("NSPrivacyAccessedAPITypes")
    require(isinstance(api_types, list), "Missing required-reason API declarations")
    for item in api_types:
        require(isinstance(item, dict) and isinstance(item.get("NSPrivacyAccessedAPIType"), str)
                and bool(item["NSPrivacyAccessedAPIType"].strip())
                and isinstance(item.get("NSPrivacyAccessedAPITypeReasons"), list)
                and bool(item["NSPrivacyAccessedAPITypeReasons"])
                and all(isinstance(reason, str) and bool(reason.strip())
                        for reason in item["NSPrivacyAccessedAPITypeReasons"]),
                "Invalid required-reason API declaration")


def apple_tool(*args):
    result = subprocess.run(args, capture_output=True, check=False)
    require(result.returncode == 0, f"{args[0]} verification failed")
    return result.stdout


def check_signature(bundle, info, group, team):
    apple_tool("codesign", "--verify", "--strict", str(bundle))
    data = apple_tool("codesign", "-d", "--entitlements", ":-", str(bundle))
    try:
        entitlements = plistlib.loads(data)
    except Exception as error:
        raise ValidationError("Cannot decode signed entitlements") from error
    require(entitlements.get("com.apple.security.application-groups") == [group],
            "Signed App Group does not match bundle configuration")
    signed_team = entitlements.get("com.apple.developer.team-identifier")
    require(isinstance(signed_team, str) and bool(signed_team), "Missing signed team identifier")
    require(team is None or signed_team == team, "App and extension signing teams differ")
    application_id = f"{signed_team}.{info['CFBundleIdentifier']}"
    require(entitlements.get("application-identifier") == application_id,
            "Signed application identifier mismatch")
    require(entitlements.get("get-task-allow", False) is False,
            "Distribution validation rejects debug entitlements")
    profile_path = bundle / "embedded.mobileprovision"
    require(profile_path.is_file(), "Distribution bundle is missing provisioning profile")
    profile = plistlib.loads(apple_tool("security", "cms", "-D", "-i", str(profile_path)))
    expiration = profile.get("ExpirationDate")
    require(isinstance(expiration, datetime.datetime), "Profile is missing expiration")
    require(expiration.replace(tzinfo=datetime.timezone.utc) > datetime.datetime.now(datetime.timezone.utc),
            "Provisioning profile expired")
    require(signed_team in profile.get("TeamIdentifier", []), "Profile team mismatch")
    allowed = profile.get("Entitlements", {})
    require(fnmatch.fnmatchcase(application_id, allowed.get("application-identifier", "")),
            "Profile does not authorize application identifier")
    require(group in allowed.get("com.apple.security.application-groups", []),
            "Profile does not authorize App Group")
    require(allowed.get("get-task-allow", False) is False, "Profile permits debugging")
    require(not profile.get("ProvisionedDevices") and not profile.get("ProvisionsAllDevices"),
            "App Store validation requires a distribution profile, not ad hoc or enterprise")
    return signed_team


def validate(app, require_signing=False, check_binary=True):
    info = read_plist(app / "Info.plist")
    identifier = info.get("CFBundleIdentifier", "")
    group = info.get("SpamHoleAppGroupIdentifier", "")
    require(isinstance(identifier, str) and bool(re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", identifier)),
            "Invalid app identifier")
    require(isinstance(group, str) and bool(re.fullmatch(r"group\.[A-Za-z0-9.-]+", group)), "Invalid App Group")
    require(info.get("CFBundlePackageType") == "APPL", "Root bundle must be an application")
    require(info.get("UIDeviceFamily") == [1], "Release must target iPhone only")
    require(bool(info.get("NSContactsUsageDescription")), "Missing Contacts purpose string")
    require(info.get("BGTaskSchedulerPermittedIdentifiers") ==
            [identifier + ".refresh", identifier + ".processing"], "Background identifier mismatch")
    require(info.get("ITSAppUsesNonExemptEncryption") is False, "Encryption answer requires review")
    require(bool(info.get("CFBundleIcons")), "Missing compiled app icon declaration")
    expected = {
        "CallDirectory": "com.apple.callkit.call-directory",
        "MessageFilter": "com.apple.identitylookup.message-filter",
    }
    plugins = list((app / "PlugIns").glob("*.appex"))
    require({p.stem for p in plugins} == set(expected), "Expected exactly two protection extensions")
    team = None
    for bundle in [app] + sorted(plugins):
        settings = read_plist(bundle / "Info.plist")
        resolved(settings)
        require(settings.get("UIDeviceFamily") == [1], "Release bundles must target iPhone only")
        bundle_id = identifier if bundle == app else identifier + "." + bundle.stem
        require(settings.get("CFBundleIdentifier") == bundle_id, "Bundle identifier mismatch")
        require(settings.get("SpamHoleContainingAppIdentifier") == identifier,
                "Containing app identifier mismatch")
        require(settings.get("SpamHoleAppGroupIdentifier") == group, "App Group configuration mismatch")
        for key in ("CFBundleShortVersionString", "CFBundleVersion"):
            require(isinstance(settings.get(key), str) and bool(settings[key])
                    and settings[key] == info.get(key), "App and extension version mismatch")
        require(settings.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], "Expected a device build")
        executable_name = settings.get("CFBundleExecutable", "")
        require(bool(executable_name) and Path(executable_name).name == executable_name,
                "Invalid executable name")
        executable = bundle / executable_name
        require(executable.is_file(), "Missing executable")
        if check_binary:
            arches = apple_tool("xcrun", "lipo", "-archs", str(executable)).decode().split()
            require(arches == ["arm64"], "Release executable must contain only device arm64")
            build = apple_tool("xcrun", "vtool", "-show-build", str(executable)).decode()
            require(re.findall(r"^\s*platform\s+(\S+)\s*$", build, re.MULTILINE) == ["IOS"],
                    "Executable Mach-O platform must be iOS device")
        check_privacy(bundle)
        if bundle != app:
            extension = settings.get("NSExtension", {})
            require(extension.get("NSExtensionPointIdentifier") == expected[bundle.stem],
                    "Extension point mismatch")
            require(bool(extension.get("NSExtensionPrincipalClass")), "Missing extension principal class")
            if bundle.stem == "MessageFilter":
                require("ILMessageFilterExtensionNetworkURL" not in extension.get("NSExtensionAttributes", {}),
                        "SMS filtering must not defer sender data to a network service")
        if require_signing:
            team = check_signature(bundle, settings, group, team)
    return identifier


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    paths = parser.add_mutually_exclusive_group(required=True)
    paths.add_argument("--app", type=Path, help="Built device .app")
    paths.add_argument("--archive", type=Path, help=".xcarchive containing the app")
    parser.add_argument("--require-signing", action="store_true",
                        help="Require coherent App Store profiles and signed entitlements")
    args = parser.parse_args()
    try:
        app = args.app
        if args.archive:
            archive_info = read_plist(args.archive / "Info.plist")
            applications = list((args.archive / "Products" / "Applications").glob("*.app"))
            require(len(applications) == 1, "Archive must contain exactly one application")
            app = applications[0]
            require(archive_info.get("ApplicationProperties", {}).get("ApplicationPath") ==
                    "Applications/" + app.name, "Archive application path mismatch")
        identifier = validate(app, require_signing=args.require_signing)
        scope = "signed distribution packaging" if args.require_signing else "unsigned packaging only"
        print(f"PASS: {identifier}: {scope}. Device behavior and App Store acceptance remain separate.")
    except (ValidationError, OSError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"FAIL: {error}\n")


if __name__ == "__main__":
    main()
