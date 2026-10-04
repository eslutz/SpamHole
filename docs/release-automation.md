# Automated release validation

CI runs shared-core/reference tests, synthetic hosted/UI simulator tests, public
site validation, packaging-validator regression tests, and Gitleaks. The iOS job
uses GitHub's `xcode-27` runner with Xcode 27.0 and a small iPhone 17e simulator.
XcodeGen 2.46.0 is pinned and its download is checksum-verified. Preview runner
availability can change; a queued or unavailable job is not a passing test.

The iOS job also creates an **unsigned** Release archive with a custom example
identity. This verifies the generated project and packaging without exposing
signing credentials. It is not installable distribution evidence. Performance
tests remain in their isolated scheme and are not substituted for device traces.

## Validate a built artifact

```sh
python3 -B scripts/test-release-validation.py
python3 -B scripts/validate-release.py --archive /path/to/SpamHole.xcarchive
python3 -B scripts/validate-release.py --app /path/to/SpamHole.app
```

The validator checks the containing app and exactly one Call Directory extension: expanded
custom identifiers, shared group configuration, versions, executable presence,
device arm64 architecture, extension points, icon declaration, Contacts purpose,
background identifiers and bundled privacy manifests. It rejects unexpected
extension bundles or extension points. It rejects tracking and unreviewed data collection declarations. This
is a consistency check, not a full required-reason API or privacy audit.

For an App Store archive signed using your ignored local configuration:

```sh
python3 -B scripts/validate-release.py --archive /path/to/SpamHole.xcarchive --require-signing
```

Signed mode additionally verifies code signatures, application/team identifiers,
App Group entitlements and profiles, profile expiry, and absence of debug,
ad-hoc or enterprise distribution profiles. It does not export/upload the app,
contact App Store Connect, establish Apple's acceptance, or prove device access
to the shared group. Keep signing material and raw captures out of Git.

## Public pages

`docs/site/` contains only the home, privacy and support pages plus local CSS.
`python3 -B scripts/validate-site.py` checks its allowed payload, document metadata,
local links/anchors and absence of active content or private operational markers.
The Pages workflow deploys that folder alone, never the complete `docs/` tree.
It runs on relevant main-branch changes or manual workflow dispatch. Public
support uses GitHub issues; security vulnerabilities use private reporting.

Physical cellular callbacks, VoiceOver behavior, Contacts permissions and device
performance remain pending a connected phone. No user-led checklist is required.
Final submission review and signed distribution remain separate gates. The
call-only product has no SMS-feed requirement or message access.
