#!/usr/bin/env python3
"""Agent-run performance capture. No production data setup or device reset."""
import argparse
import datetime
import hashlib
import json
import pathlib
import platform
import shlex
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", required=True,
                        help="Explicit xcodebuild destination, e.g. platform=iOS,id=<UDID>")
    parser.add_argument("--output", type=pathlib.Path, required=True,
                        help="New evidence directory; existing directories are refused")
    parser.add_argument("--only-testing", action="append", default=[],
                        help="Optional XCTest identifier, e.g. SpamHoleAppTests/OfflinePerformanceTests/testLookup50k")
    parser.add_argument("--dry-run", action="store_true", help="Print exact commands without creating files")
    args = parser.parse_args()
    output = args.output.expanduser().resolve()
    result = output / "performance.xcresult"
    command = ["xcodebuild", "test", "-project", str(ROOT / "SpamHole.xcodeproj"),
               "-scheme", "SpamHolePerformance", "-configuration", "Debug",
               "-destination", args.destination, "-parallel-testing-enabled", "NO",
               "-derivedDataPath", str(output / "DerivedData"), "-resultBundlePath", str(result)]
    command += ["-only-testing:" + item for item in args.only_testing]
    extracts = [(["xcrun", "xcresulttool", "get", "test-results", kind, "--path", str(result)],
                 output / (kind + ".json")) for kind in ("summary", "metrics")]
    if args.dry_run:
        print(shlex.join(command))
        for invocation, path in extracts:
            print(shlex.join(invocation) + " > " + shlex.quote(str(path)))
        return 0
    output.mkdir(parents=True, exist_ok=False)
    context = {"created_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "destination": args.destination, "scheme": "SpamHolePerformance",
               "capture_host": platform.platform(),
               "configuration": "Debug", "command": command,
               "interpretation": "Baseline evidence, not physical Release performance acceptance"}
    try:
        version = subprocess.run(["xcodebuild", "-version"], capture_output=True, text=True, timeout=20)
        context["xcode_version"] = version.stdout.strip() or version.stderr.strip()
    except subprocess.TimeoutExpired:
        context["xcode_version"] = "Unavailable: toolchain query timed out"
    inputs = [ROOT / "project.yml", ROOT / "Package.swift"]
    for folder in ("App", "Sources", "Extensions", "Configuration", "Tests"):
        inputs.extend(path for path in (ROOT / folder).rglob("*") if path.is_file())
    hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in sorted(inputs)}
    (output / "source-manifest.json").write_text(json.dumps(hashes, indent=2) + "\n")
    (output / "context.json").write_text(json.dumps(context, indent=2) + "\n")
    with (output / "test.log").open("w") as log:
        status = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT).returncode
    context["xcodebuild_exit_code"] = status
    for invocation, path in extracts:
        capture = subprocess.run(invocation, capture_output=True, text=True)
        if capture.returncode == 0:
            path.write_text(capture.stdout)
        else:
            path.with_suffix(".error.txt").write_text(capture.stderr)
    (output / "context.json").write_text(json.dumps(context, indent=2) + "\n")
    print("Evidence: " + str(output))
    return status


if __name__ == "__main__":
    sys.exit(main())
