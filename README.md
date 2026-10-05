# SpamHole

An offline iPhone call-reputation and call-blocking app. Publishers supply
downloaded evidence; reputation and matching stay on your device. There are no
incoming-call lookups, accounts, ads, or telemetry. SpamHole has no access to messages.

**Development build. Version 2 automatic-call acceptance, classification quality,
retained-memory stability and distribution review remain open; see `docs/release-checklist.md`.**
SpamHole downloads FTC evidence, computes reputation locally, and generates an
automatic blocklist using Conservative, Balanced or Aggressive. Review the local
count once to activate; subsequent refreshes update the list automatically.
Personal Allow/Block rules are overrides. FTC reports are unverified; the indices
are heuristics, not probabilities or proof of genuine origination.

## Build

Requires Xcode 27 and XcodeGen. Deployment target: iOS 26, iPhone.

```sh
xcodegen generate
open SpamHole.xcodeproj
```

For a physical device, copy `Configuration/Local.xcconfig.example` to
`Configuration/Local.xcconfig`, set your bundle identifier, App Group and signing
team, then regenerate the project. The local override is ignored by Git. Register
your App Group for the app and its Call Directory extension. See [configuration](docs/configuration.md).
Build and install the `SpamHole` scheme. Enable its Call Directory extension in Settings. Simulator tests do not prove
cellular call behavior.

Normal simulator runs need signing enabled so Xcode supplies simulated App Group
entitlements. Local ad hoc signing works without distribution credentials.
`CODE_SIGNING_ALLOWED=NO` is suitable for compilation and the isolated UI-test
mode, but the normal app then reports an unavailable shared container.

Run the shared-engine tests with workspace-local caches:

```sh
swift test --scratch-path .build --cache-path .build/cache
python3 -B spam_reputation_reference_20261003.py  # historical version 1
python3 -B scripts/local-inference-reference.py  # production version 2
```

## Design

- `App`: SwiftUI interface, refresh coordinator, contacts, Keychain, background work.
- `Sources/SpamHoleCore`: normalized evidence, SQLite storage, source adapters,
  deterministic reputation, immutable snapshots, and call decisions.
- `Extensions`: Call Directory loading.
- `docs`: source findings, privacy, review notes, and device/release gates.

Downloads, computed snapshots, and successful iOS installations are distinct
states. Background updates are best-effort. Installed Call Directory entries
cannot expire until a successful reload; stale state is visible in the app.

The original confirmation-gated Python model is retained as historical version 1.
Production uses the [version 2 local-inference policy](docs/local-blocking.md),
with independent numerical fixtures. Coefficients are proposed heuristics, not
empirically calibrated estimates. Only catalog-reviewed sources contribute to
local blocking; custom feeds cannot grant eligibility or confirmation. FTC is
eligible for inference without being treated as verified origin evidence.
App Store acceptance of this model remains an explicit distribution gate.

Original app code is MIT licensed. Dataset rights remain with each publisher.

CI includes synthetic iOS simulator tests and unsigned Release archive validation.
See [release automation](docs/release-automation.md) for artifact validation and its
limits. Public privacy/support pages are maintained in `docs/site/` and deployed
separately from app distribution.
The public [privacy policy](https://spamhole.ericslutz.dev/privacy.html) and
[support page](https://spamhole.ericslutz.dev/support.html) describe the
development version; their publication does not establish app release readiness.

See [development status](docs/status.md), [source qualification](docs/sources.md),
[release gates](docs/release-checklist.md), [contributing](CONTRIBUTING.md), and
[security policy](SECURITY.md). Local operational reports and unpublished
App Store materials are intentionally excluded from the public repository.
