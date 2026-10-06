# Additional call sources validation

Date: October 5, 2026. Scope: FCC, PhoneBlock and CallShield normalization and
integration. Results do not establish classification accuracy, physical call
suppression, TestFlight acceptance or production readiness.

## Implemented behavior

FCC and CallShield are optional disabled built-ins; existing subscriptions keep
their enabled state. PhoneBlock is implemented with synthetic full/delta coverage,
Keychain token editing and a closed publisher-clearance activation gate. All source
records normalize before storage/scoring. Aggregate votes and reviews contribute
bounded evidence, never observed-call days or confirmation authority. Government
mirrors in CallShield are excluded. Personal-rule precedence is unchanged.

Replacements commit evidence and checkpoints atomically using import revisions.
Contact/cadence updates use the same current-source/revision protection. Malformed
or interrupted imports retain the last complete dataset; PhoneBlock supported-row
schema errors retain its checkpoint. Structurally unsupported countries are
excluded and counted. Future expansion of country metadata requires a fresh
PhoneBlock full snapshot so previously excluded rows can be recovered.

## Evidence

- Core Debug and Release: **80 tests passed in each configuration**, including legacy decoding, aggregate persistence,
  expiry and authority, exact German/Italian numbers, FCC dates/voice roles,
  PhoneBlock buckets/removals/cadence/credential rotation, CallShield signature,
  digest/path/provenance checks and stale-checkpoint rejection.
- Numerical reference: **123 V1 checks passed**; V2 policy/expiry/nesting checks
  passed with unchanged fixtures.
- Packaging rejection logic: **13 tests passed**. Static public site: **3 pages
  passed** payload/link validation.
- Public FCC refresh through Swift transport, normalization, transaction and
  persisted readback: **15,364 event records accepted; 10,119 excluded**, 18 seconds.
  Query selected only the 90-day voice-call window and displayed caller-ID field;
  publication metadata was checked before and after paging.
- Public CallShield refresh through pinned signature verification, all signed
  shards, normalization, transaction and persisted readback: **1 community summary
  accepted; 120 structurally invalid/unsupported rows counted**, 37 seconds.
  Provenance/rights/expiry exclusions are additional to this invalid-row count;
  most government/database-origin rows are intentionally outside the integration.

- Hosted simulator: **22 tests passed** in an ad hoc signed app, including real
  Keychain credential rotation, migration, access gating and 250,000-assessment
  snapshot publication/readback. An unsigned run could not access Keychain; the
  signed rerun passed without a test bypass.
- Affected simulator UI: **2 tests passed**, covering the PhoneBlock access gate,
  secure token editor, onboarding and all tabs. These are simulator results.

## Review and discovered regressions

One fresh-context whole-change review found a delayed HTTP 304 could overwrite a
newer checkpoint. The regression was observed failing before an atomic state-update
fix, then passed in the full suite. Revision validation now occurs inside the SQLite
transaction for replacements as well.

The existing hosted 250,000-assessment regression also exposed snapshot bloat from
per-assessment counts. Event-only assessments retain their prior compact encoding;
counts are stored when community summaries are present. The existing 128 MiB read
bound is retained. A credential-editor catch variable triggered a Swift compiler
assertion; explicit error naming corrected the source.

Normal Release archive compilation and unsigned packaging validation passed.
The archive includes the call-only extension; no Release testability or Debug
bypass was enabled. Gitleaks 8.30.1 found no leaks in the intended public payload.
CI simulator tests now use ad hoc signing so real Keychain tests run without
signing credentials; distribution archive validation remains unsigned.

## Implementation decisions

- Use the existing feature branch and ignored private artifact directory. This
  avoids extra checkouts/configuration churn; interrupted-run evidence remains
  local until this task's scratch directory is removed.
- Preserve V1's synthetic trust inputs for numerical parity, while production
  storage and official aggregates still canonicalize catalog authority. Passing
  arbitrary sources directly to the pure legacy evaluator is not app authority.
- Recovery compares the persisted pre-failure state, including new revision/count
  metadata, rather than an earlier constructed value. This verifies the actual
  rollback baseline.
- Exclude unsupported PhoneBlock countries but reject malformed supported records
  without advancing the checkpoint. Newly supported countries require a later
  full snapshot; their coverage is incomplete until then.
- Store per-assessment counts when summaries exist. Event-only snapshots retain
  their size bound; clients must treat missing summary counts as legacy/event-only.
- Keep publisher authorization, live compatibility, physical call acceptance and
  VoiceOver separate. Public imports passed; PhoneBlock access and existing device
  gates are not established by code tests. No minor review findings were deferred.

## Reproduction and limits

Run `swift test --disable-sandbox --jobs 2` and its Release equivalent; test the
`SpamHole` scheme for hosted and affected UI coverage. Regenerate the project after
changing its test selection: `scripts/generate-project.sh`.

For a public transport smoke check, compile and run serially:

```sh
xcrun swiftc -parse-as-library -module-cache-path .build/source-validation-modules \
  -I Sources/CSQLite Sources/SpamHoleCore/*.swift \
  scripts/validate-additional-sources.swift -o .build/validate-additional-sources
.build/validate-additional-sources
```

The tool uses an isolated disposable private store and emits only counts and
controlled errors. Do not publish raw records, contact identifiers, credentials or
logs. Live publisher counts can change. PhoneBlock registration/data-use clearance,
an authorized account/token and measured regional coverage remain open; no live
PhoneBlock request was made. These checks did not modify the physical iPhone.
Existing device/accuracy/distribution gates remain separate.
