# Development status

SpamHole is an open-source, call-only development application, not a
production-approved App Store release. Personal call allow/block rules, local
snapshots, call identification, source refresh and the Call Directory extension
are implemented. The user retired SMS filtering on October 4, 2026; there is no
message access or SMS-feed release requirement.

FTC allegations support neutral identification, not automatic blocking. A
complete 24-shard FTC refresh was verified on this host through the actual Swift
downloader and SQLite store. Physical verification on October 5 confirmed a completed
phone import with 259,721 records, enabled Call Directory, and a matching installation
receipt for 52 identification entries. A reserved synthetic personal block was installed
and removed with verified receipts, restoring zero blocking entries. These receipts do
not establish actual incoming-call outcomes. See the [dated FTC report](research/ftc-source-availability-2026-10-04.md).

On October 4, 2026, development-signed installation and update over Wi-Fi were
verified on an iPhone 18 Pro Max running iOS 27. All 22 hosted/UI device tests and
seven isolated Debug performance tests passed; 51 core tests passed on the host.
These suites bypass real Call Directory installation. At 250,000 synthetic
entries, snapshot load averaged 1.45 seconds and rebuild 9.88 seconds. The rebuild
harness recorded a 1,156 MiB whole-process peak, including fixture/setup effects;
Release allocation tracing remains necessary.

Release testing found valid labels were rejected by nested control-character
predicates. Explicit validation fixes both saved JSON and binary call exports;
52 core tests now pass in Debug and Release, and the physical Release app reads
its saved 226,265 assessments. CI includes optimized core tests. See the
[physical validation summary](performance/physical-validation-2026-10-05.md).

Normal Release interaction testing subsequently passed three process launches and
20 additional Lookup/scrolling/sheet cycles, plus three Home/foreground cycles.
Physical Contacts authorization was
read without requesting access; it remains not determined. Follow-up CPU traces
were empty and the allocation capture had no allocation tables, so functional
interaction success does not close performance acceptance.

Physical calls, Contacts changes, native extension capacity, Release performance,
VoiceOver behavior, signed archive validation and distribution remain release gates. See
[release requirements](release-checklist.md) and [source qualification](sources.md).
Private operational reports and raw captures remain local; they are not included
as public release proof. Contributors should rerun tests for their checkout.
