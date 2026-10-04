# Contributing

Use Xcode 27, Swift 6 and XcodeGen for the iOS application (iOS 26 minimum).
Regenerate the project using `scripts/generate-project.sh`. Follow the
[local configuration guide](docs/configuration.md) for your own signing identity.

Run `swift test` and `python3 -B spam_reputation_reference_20261003.py` for the
shared engine/reference checks. Run the generated `SpamHole` scheme for hosted
and UI tests. The separate `SpamHolePerformance` scheme uses synthetic isolated
fixtures; see [profiling](docs/performance/offline-profiling.md).

Keep changes focused and add regression coverage for behavioral changes. Use
synthetic telephone numbers and temporary stores. Never attach actual contact/message
records, source tokens, signed artifacts or private device logs to issues/PRs.
Report security issues privately as described in [SECURITY.md](SECURITY.md).

Preserve offline incoming-number matching, explicit user-rule precedence and
reviewed source authority. The product is call-only: do not add message access
or message-filtering behavior. Code
licensing does not qualify upstream data; document dataset rights separately.
