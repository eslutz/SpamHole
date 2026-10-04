# Development status

SpamHole is an open-source development application, not a production-approved
App Store release. Personal call/SMS rules, local snapshots, call identification,
source refresh and the two extensions are implemented. FTC allegations only
support neutral identification. No reviewed free/open source currently qualifies
for automatic SMS Junk reputation decisions.

Core and simulator tests provide local behavior evidence. Physical calls/SMS,
Contacts changes, large-device capacity/performance, signing, VoiceOver behavior,
archive validation and distribution remain release gates. See
[release requirements](release-checklist.md) and [source qualification](sources.md).
Private operational reports and raw captures remain local; they are not included
as public release proof. Contributors should rerun tests for their checkout.
