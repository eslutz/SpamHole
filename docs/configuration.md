# Configuration

Copy `Configuration/Local.xcconfig.example` to `Configuration/Local.xcconfig`.
Set `SPAMHOLE_BUNDLE_IDENTIFIER`, `SPAMHOLE_APP_GROUP` and optionally
`DEVELOPMENT_TEAM` for your own Apple Developer account, then run
`scripts/generate-project.sh`. Xcode applies the same identity to the app,
extensions, background tasks, shared storage and Keychain namespace.

Public defaults match the original app identity. A local override is optional;
unit tests and unsigned compilation do not require a signing team. A device
installation requires matching registered identifiers, provisioning and App
Group entitlements for all three targets. Changing identity creates separate
storage/Keychain namespaces; it does not migrate existing rules or credentials.

No `.env` or server secret is required. Source URLs, cadence and private rules
are configured in the app. Source bearer tokens are entered in source settings
and kept in Keychain, never in xcconfig, source code or a committed example.
Custom feeds cannot grant themselves confirmation authority.

Never commit signing keys/profiles, local xcconfig, database exports, contact
lists, message data, logs, raw device traces or unpublished account metadata.
The generated Xcode project is ignored so local signing edits cannot be published
accidentally; `project.yml` and public configuration templates are the source of truth.
