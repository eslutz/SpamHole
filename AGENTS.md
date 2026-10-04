# Repository Guidelines

## Project Structure & Module Organization

- `App/`: SwiftUI views, app state, Contacts, Keychain, and background services. Assets live in `App/Assets.xcassets`.
- `Sources/SpamHoleCore/`: shared reputation engine, SQLite storage, source adapters, normalization, and snapshots; `Sources/CSQLite/` bridges SQLite.
- `Extensions/`: Call Directory and Message Filter targets.
- `Tests/`: core, hosted app, and UI XCTest suites; numerical fixtures live in `Tests/SpamHoleCoreTests/Fixtures/`.
- `Configuration/`, `project.yml`, and `scripts/`: build settings, manifests, XcodeGen specification, and tooling. `docs/` describes source contracts and release gates.

## Build, Test, and Development Commands

Requires Xcode 27, Swift 6, and XcodeGen; the app targets iPhone on iOS 26+.

- `scripts/generate-project.sh`: regenerate the ignored `SpamHole.xcodeproj` from `project.yml`.
- `open SpamHole.xcodeproj`: open Xcode; build/run the `SpamHole` scheme on a selected simulator or configured device.
- `swift test`: run shared-engine tests.
- `python3 -B spam_reputation_reference_20261003.py`: run reference-model parity checks.
- `python3 -B scripts/test-release-validation.py`: test artifact rejection logic; `scripts/validate-release.py --archive PATH` checks packaging. Signed distribution checks require `--require-signing`.
- `python3 -B scripts/validate-site.py`: validate the isolated public privacy/support site payload.
- Test the `SpamHole` scheme for hosted/UI coverage; use `SpamHolePerformance` only for isolated profiling.

## Coding Style & Naming Conventions

Use four-space indentation, `UpperCamelCase` types, and `lowerCamelCase` functions/properties. Match existing SwiftUI composition and Swift 6 concurrency isolation. Keep domain work in the shared core or service actors, outside view rendering. Use descriptive filenames matching principal types. No formatter or lint configuration is currently enforced; avoid unrelated reformatting.

## Testing Guidelines

Add meaningful regression tests for behavioral changes. Name tests `test` followed by the expected behavior. Use synthetic senders and temporary stores; test invalid input, cancellation, expiry, and last-good-state recovery when applicable. No numeric coverage threshold is defined. CI runs core/reference, hosted/UI, packaging and site checks plus Gitleaks; simulator success does not establish physical call/SMS or VoiceOver acceptance.

## Commit & Pull Request Guidelines

Use concise imperative subjects, following existing descriptive commits without requiring Conventional Commits. PRs should explain the problem, resulting behavior, relevant test results, and remaining limits; link applicable issues and include synthetic-data screenshots for UI changes. Preserve unrelated work.

## Security & Configuration

Copy `Configuration/Local.xcconfig.example` to the ignored `Local.xcconfig` for custom identity/signing. Never commit credentials, signing material, personal data, or raw device logs. Preserve offline sender matching, fail-open SMS behavior, user-rule precedence, and reviewed source authority. Follow `SECURITY.md`; do not claim production readiness while release gates remain open.
