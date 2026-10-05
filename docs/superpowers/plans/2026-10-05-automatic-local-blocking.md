# Automatic Local Blocklist Generation Implementation Plan

Approved in conversation on October 5, 2026. This replaces identification-only V1 as the product direction.

## Goal and decisions

Download evidence directly from free, reviewed publishers, compute reputation locally, apply Conservative/Balanced/Aggressive, and install automatic blocks in iOS. Personal rules are overrides. No SMS, server lookup, analytics or uploaded Contacts. Existing installations review the generated count once before activation; subsequent updates run automatically. New installations start with Balanced and review before activation.

Version 2 retains normalization, stable deduplication, independent family grouping, daily cap 5, seven-day evidence half-life, 90-day evidence window, source-freshness weighting, and family aggregation. For eligible sources, R is the complaint report index; D is the distinct observed call dates within 14 days; L = R × (0.5 + 0.5 × min(1, D / 4)) × (1 − positivePenalty) × (1 − uncertaintyPenalty). Retain the burst penalty. L is an inference index, not confirmation or a probability. Source freshness is already in R and must not be multiplied twice.

Automatic eligibility requires an exact displayed caller, enabled catalog-approved local-inference source, publisher coverage at most seven days old, and an observed call at most seven days old. Undated evidence cannot establish recent events or persistence. Thresholds (R / L / days): Conservative 90 / 90 / 4; Balanced 85 / 75 / 3; Aggressive 75 / 60 / 2. Keep identification thresholds. No block hysteresis.

FTC is initially eligible, with confirmation grade still zero. Unknown custom sources cannot self-authorize. Additional sources require rights, caller-number semantics, freshness, corrections and lineage review; FCC is a candidate, not an assumed eligible source.

Precedence: Allow, personal Block, protected Contacts, automatic policy. Capacity 25,000: reserve personal blocks, then rank automatic candidates by L descending, R descending, number ascending. Never silently discard personal blocks. Keep exports sorted, unique and disjoint; preserve atomic publication and matching installation receipts.

## Tasks

### Task 1: Core inference and exports

- [ ] Add failing FTC-only, policy nesting, preview, expiry, override and capacity tests.
- [ ] Add compatible settings/source eligibility, optional assessment decisions and scoring/count metadata. Missing activation decodes false; missing eligibility decodes false. Binary formats stay unchanged.
- [ ] Compute eligible-source inference and export automatic blocks when activated; explain all exclusions. Recompute older generations from evidence.
- [ ] Add version 2 reference fixtures/parity and run `swift test --jobs 2` plus both Python references.

### Task 2: Activation and product UI

- [ ] Add hosted regressions for activation, policy changes, disabling and receipt preservation.
- [ ] Add one-time review sheet, off switch and setup path. Counts must distinguish eligibility, computed blocks and receipt-verified installed blocks. Show source eligibility and Lookup decision reasons.
- [ ] Run affected hosted and UI tests serially. Do not confuse simulator with incoming-call acceptance.

### Task 3: Evidence and documentation

- [ ] Evaluate actual FTC data privately; publish only aggregate score distributions and per-policy counts, never numbers or raw data. Do not lower thresholds to manufacture counts.
- [ ] Update source, website, onboarding, README, App Review and release descriptions. Add labelled-data quality gate: FTC membership is not ground truth.
- [ ] Test site and packaging rejection logic; add version 2 reference parity to CI.

### Task 4: Verification and delivery

- [ ] Run core in Debug/Release, affected hosted/UI, parity, packaging/site checks, secret scan and fresh review. Use bounded serial builds within host disk/RAM limits.
- [ ] Physical acceptance uses an isolated Release container and authorized caller: inferred block without personal Block, Allow recovery and cleanup. Record blocked if a phone/observer is unavailable; no manual checklist or substitute simulator acceptance. VoiceOver remains waived.
- [ ] Commit and push sanitized changes. Automatic installation acceptance, independent labelled-data quality, retained-memory stability and App Store acceptance remain separate gates.

## Review focus

Forged catalog approvals; source coverage ageing without a network refresh; legacy settings/backups unintentionally enabling blocking; capacity exclusions misrepresented as installed blocks; activation or policy changes racing snapshot publication. Each requires regression coverage.

## Distribution constraint

FTC reports are unverified. The selected local-inference model replaces the research's separate confirmation requirement; it does not establish compliance with Apple's confirmed-spam requirement or public-release readiness. Do not fabricate confirmation or hide this open gate.
