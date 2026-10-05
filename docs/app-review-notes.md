# App Review preparation

SpamHole is call-only. It uses public CallKit Call Directory APIs to install local
telephone-number identification and blocking lists. Incoming calls do not trigger
server queries. There is no live caller lookup extension, Message Filter
extension, message access, public crowdsourcing service, or nonstandard
background mode.

Version 2 computes local-inference automatic blocklists from FTC reports using
recency, persistence, source quality, uncertainty and the selected policy. Users
review the computed count once before activation; personal rules are overrides.
FTC complaints remain unverified and receive no origin-confirmation grade.
Custom lists remain identification-only and cannot self-authorize blocking.

Apple guideline 2.5.12 requires blocked numbers to be confirmed spam. This
inference model has not received App Review acceptance; do not describe its
heuristics as confirmation or submit a misleading confirmation-only explanation.
Classification-quality evaluation and distribution acceptance remain open.

The containing app periodically refreshes complete datasets when iOS grants
execution opportunities. Requested cadence is not a guaranteed timer. The app
shows data refresh, snapshot generation and Call Directory installation state
separately. Installed call entries have no per-entry expiration API.

Public submission remains pending version 2 physical-call acceptance, independent
classification-quality evaluation, retained-memory stability, signing and
distribution review. Physical VoiceOver testing was waived, not passed. Complete this document with the
release candidate's source contract, recorded acceptance results, reviewer
instructions and a reviewable TestFlight build before use. Historical SMS
research is outside the current product scope and is not a release requirement.
