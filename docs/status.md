# Development status

SpamHole is a call-only, open-source development application. Version 2 restores
the intended workflow: download free FTC complaint evidence, calculate reputation
locally, apply Conservative, Balanced or Aggressive, and generate automatic iOS
Call Directory blocks. Users review once before activation; later updates use the
saved policy. Personal Allow/Block rules and accessible Contacts provide overrides.
SMS filtering was retired on October 4, 2026.

FTC allegations remain unverified. The local inference index is neither a
probability nor confirmation. The selected model replaces V1's confirmation gate;
it does not establish accuracy or App Store acceptance. Custom sources cannot
self-authorize blocking. See [the policy](local-blocking.md) and
[version 2 validation](validation/local-blocking-v2.md).

The prior phone import accepted 259,721 records and installed 52 identification
entries. V1 exported zero automatic blocks. Those historical counts do not describe
V2's generated blocklist. Earlier physical baseline/personal Block/personal Allow
calls, native extension recovery and synthetic Contacts transitions passed on
one iOS 27 device. They do not prove V2 reputation-generated call suppression.

The fresh October 5 host evaluation accepted 281,214 FTC records, scored 244,426
numbers, and generated 2 Conservative, 4 Balanced or 8 Aggressive automatic
blocks without personal rules or Contacts. These counts are host-computed, not
installed on the phone, and do not establish accuracy. Both core configurations,
affected hosted/UI tests and unsigned Release packaging passed; see the version 2
validation report for exact scope.
Physical VoiceOver testing was waived, not passed.

Release memory profiling found small continued growth across twenty interaction
cycles; [issue 1](https://github.com/eslutz/SpamHole/issues/1) remains open. Signed
archive/TestFlight distribution, independent labelled-data accuracy and Apple's
confirmed-spam requirement remain separate release gates. Public source availability
and simulator tests do not establish production readiness. See
[release requirements](release-checklist.md).
