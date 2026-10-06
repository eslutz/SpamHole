# Automatic local blocking validation — October 5, 2026

## Scope

Version 2 calculates FTC-based local inference and exports automatic Call Directory
blocks after one-time activation. It replaces the V1 identification-only direction.
Personal Allow, personal Block, accessible protected Contacts, and automatic
inference apply in that order. No SMS component or caller-number server query was
added. See [the scoring contract](../local-blocking.md).

## Verified results

- Core: 63 tests pass in both Debug and Release, including the additional
  mixed-format FTC regression.
- The original reference calculator passes 123 checks; the independent version 2
  calculator passes arithmetic, expiry, policy-boundary and fixture-parity checks.
- Hosted simulator: 19 tests pass, including one-time activation, stale review
  refusal, policy rebuilds, overrides, disable-during-work queuing, backup activation
  restrictions, atomic publication and receipt preservation.
- Affected simulator UI: four tests pass: activation/counts/off, cancellation at
  largest text in dark mode, onboarding/tabs, and personal Block lookup. A synthetic
  screenshot was inspected; the review title was shortened to avoid truncation.
  The final wording/title rerun passes.
- Packaging rejection: 13 tests pass. Static site: three public pages pass payload,
  link and anchor validation. The normal unsigned Release archive builds and passes
  packaging validation;
  this does not establish signing or distribution acceptance.
- Fresh independent review found no Critical or Important defect beyond the fixed
  disable-during-work race. Capacity exhaustion wording was corrected. Parser
  format/concurrency review found no additional defect.

FTC-only synthetic cases produce one Conservative, two Balanced, and three
Aggressive blocks without a confirmation feed or personal Block. Tests cover
stale coverage, missing/retracted/old observed dates, duplicates, single-day
bursts, forged source approval, overrides, capacity and legacy decoding. These
numbers are test-fixture outcomes, not real-data counts or accuracy estimates.

## Actual-data evaluation

The first opt-in fresh FTC run reached its 600-second bound without producing a
completed import; peak process-tree RSS was 132.7 MiB. A two-second sample showed
repeated date-formatter construction during CSV parsing. The parser now owns and
reuses formatters within one synchronous import, preserving format order, strict
parsing, POSIX locale and UTC interpretation; no formatter is shared across imports.
The retry completed in 397.0 seconds, including download, import and three complete
policy builds; monitored process-tree peak RSS was 624.1 MiB. This is a host workflow
measurement, not physical-device latency. Its fresh temporary database was deleted.
No raw evidence or telephone numbers are published.

Evaluation time: 2026-10-05 19:10:51 UTC. Publisher coverage: 2026-10-04 23:48:05 UTC.
The real downloader/parser/store accepted 281,214 records and produced 244,426
number assessments. No personal rules or Contacts were applied.

| Policy | Automatic blocks | Identification entries | Capacity exclusions |
| --- | ---: | ---: | ---: |
| Conservative | 2 | 42 | 0 |
| Balanced | 4 | 123 | 0 |
| Aggressive | 8 | 577 | 0 |

| Eligible-evidence index, across assessments | Median | P90 | P99 | Maximum |
| --- | ---: | ---: | ---: | ---: |
| R, report index | 1.71 | 7.34 | 12.32 | 95.61 |
| L, local blocking index | 0.86 | 2.29 | 4.74 | 95.61 |

Distributions include assessments with zero eligible contribution. Most numbers
have sparse evidence; the approved persistence and score gates admit few blocks.
Thresholds were not lowered to increase totals. This is a fresh host evaluation,
not an updated phone installation or a false-positive/recall estimate.

## Resource and privacy controls

Serial builds used bounded process-tree RSS (1.6 GiB), a 16 GiB free-disk reserve,
and a 15% reported free-memory stop. The passing hosted/UI session peaked at
168.9 MiB in its monitored command tree; simulator services are outside that tree
and were covered by the system-memory guard. No long Instruments capture was run.
Private databases, logs and result bundles stay ignored. Only aggregate findings
and synthetic fixtures belong in Git. Gitleaks found no secrets in a clean export of the staged Git index. A separate
known private-identity/caller-value check also passed.

## Open acceptance gates

- **Blocked:** physical reputation-generated incoming-call suppression, Allow
  recovery and cleanup in an isolated Release container. The reachable phone was
  locked; no recipient-side V2 observation is available. Simulator success and
  earlier V1 personal-rule calls do not clear this gate. The existing phone app,
  rule state, Contacts permission and refresh cadence were not changed this run.
- **Open:** independent, rights-cleared labelled-data evaluation. FTC membership
  is not ground truth and score distributions do not measure false positives.
- **Open:** [Apple guideline 2.5.12](https://developer.apple.com/app-store/review/guidelines/#software-requirements)
  requires confirmed spam. FTC evidence and the chosen inference model do not
  establish App Review acceptance. No submission or TestFlight upload was performed.
- **Open:** retained-memory stability, tracked by
  [issue 1](https://github.com/eslutz/SpamHole/issues/1).
- **Waived:** physical VoiceOver, as directed by the user; not passed.
- **Open:** signed distribution validation and TestFlight acceptance.

Contributor reruns must keep actual-data copies, phone identities and call recordings
private. Eligibility is nested by threshold; at capacity, L-first ranking can change
membership rather than preserve a subset relation across exported lists.
