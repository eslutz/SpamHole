#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required to regenerate SpamHole.xcodeproj from project.yml." >&2
  exit 1
fi
xcodegen generate --spec project.yml
