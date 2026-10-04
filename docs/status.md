# Development status

SpamHole is an open-source, call-only development application, not a
production-approved App Store release. Personal call allow/block rules, local
snapshots, call identification, source refresh and the Call Directory extension
are implemented. The user retired SMS filtering on October 4, 2026; there is no
message access or SMS-feed release requirement.

FTC allegations support neutral identification, not automatic blocking. A
complete 24-shard FTC refresh was verified on this host through the actual Swift
downloader and SQLite store; this does not prove physical iPhone downloads or
Call Directory behavior. See the [dated FTC report](research/ftc-source-availability-2026-10-04.md).

Core and simulator tests provide local behavior evidence. Physical calls,
Contacts changes, large-device capacity/performance, signing, VoiceOver behavior,
signed archive validation and distribution remain release gates. See
[release requirements](release-checklist.md) and [source qualification](sources.md).
Private operational reports and raw captures remain local; they are not included
as public release proof. Contributors should rerun tests for their checkout.
