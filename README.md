# SpamHole

An offline iPhone call-reputation and call-blocking app. Publishers supply
downloaded evidence; reputation and matching stay on your device. There are no
incoming-call lookups, accounts, ads, or telemetry. SpamHole has no access to messages.

**Development build. Physical-call acceptance, VoiceOver, signing and
distribution review remain open; see `docs/release-checklist.md`.**
Personal call rules provide explicit allow/block control. FTC complaints support
call identification, not automatic blocking. A high association index is not a
probability or proof of genuine origination.

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
python3 -B spam_reputation_reference_20261003.py
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

The original Python model and worked examples are retained as numerical fixtures.
The coefficients are proposed heuristics, not empirically calibrated estimates.
Only maintainer-reviewed source authority can authorize automatic call blocking;
custom feeds cannot promote their own allegations to confirmations.

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
