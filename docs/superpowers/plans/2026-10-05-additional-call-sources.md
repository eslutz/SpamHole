# Additional Call Sources Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Normalize FCC, PhoneBlock and CallShield data before applying SpamHole's local reputation policies.

**Architecture:** Source-specific adapters produce shared evidence records and transactional source checkpoints. Scoring consumes normalized event or aggregate evidence; aggregate votes never manufacture observed-call days.

**Tech Stack:** Swift 6, Foundation, SQLite, CryptoKit, SwiftUI, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-05-additional-call-sources-design.md`

## Global Constraints

- iOS 26+, offline incoming-call matching and unchanged existing policy thresholds.
- Preserve personal-rule precedence, last-good state and source authority owned by the catalog.
- No credentials, consumer data, raw feed numbers or device logs committed.
- PhoneBlock live use remains gated by publisher access and data-use clearance.
- Run builds serially with bounded downloads within available disk/RAM.

## Review Focus

- Aggregate metadata supplied by an unreviewed custom source must not acquire scored authority.
- Two refreshes suspended at the same checkpoint must not roll back a newer dataset.
- A source disabled or removed during network suspension must remain disabled or removed.
- Missing activity dates, unsupported regions and unknown categories must not acquire invented values.
- Credential rotation must invalidate the authenticated checkpoint and respect provider cadence.

### Task 1: Shared evidence and normalization

**Files:** Modify `Models.swift`, `PhoneNormalizer.swift`, `EvidenceStore.swift`, `SnapshotBuilder.swift`; add `Tests/SpamHoleCoreTests/AdditionalSourceTests.swift`.

**Interfaces:** Optional `EvidenceKind`, aggregate vote/activity/category/expiry metadata on `EvidenceRecord`; optional checkpoint and scheduling fields on `SourceState`. Existing decoders keep legacy event behavior. Scoring uses the existing aggregate membership helper and real observed dates only.

- [x] Add failing tests for aggregate score contribution without observed days, legacy decoding, expiry, unreviewed authority and German/Italian exact numbers.
- [x] Run `swift test --jobs 2 --filter AdditionalSourceTests`; inspect expected failures.
- [x] Implement normalized metadata and shared validation; distinguish aggregate and event contributions, taking the stronger value for each originating family.
- [x] Run `swift test --jobs 2`; require a green complete core suite.

### Task 2: Official adapters and verified downloads

**Files:** Add `FCCSourceAdapter.swift`, `PhoneBlockSourceAdapter.swift`, `CallShieldSourceAdapter.swift`, `OfficialSourceRefresh.swift`; modify `SourceAdapters.swift`, `SourceCatalog.swift`, `SourceDownloader.swift`; add adapter/download tests.

**Interfaces:** Adapters parse publisher bytes into `ParsedSourceImport`; PhoneBlock returns typed additions/removals/version; verified refresh produces complete evidence and matching state for one transaction.

- [x] Add failing synthetic tests for FCC voice filtering/date quality, PhoneBlock bucket/removal semantics, CallShield signatures/digests/lineage and interrupted imports.
- [x] Run targeted tests and observe expected failures before implementing adapters.
- [x] Add reviewed catalog entries, voice-only FCC paging, PhoneBlock transactional deltas/cadence, and verified CallShield shard loading with app-owned source allowlists.
- [x] Add checkpoint comparison at commit, rollback protection and retained last-good behavior.
- [x] Run `swift test --jobs 2`; require all adapter, state and existing recovery tests to pass.

### Task 3: App integration and status

**Files:** Modify `App/AppModel.swift`, `App/Views/SourcesView.swift`, `App/Views/LookupView.swift`, `App/Services/ProtectionPipeline.swift`; add hosted/UI regression coverage where behavior changes.

**Interfaces:** Built-ins install without changing prior enabled states; source-specific status and credential editing use existing Keychain isolation. A credential change clears authenticated evidence/checkpoint association and rebuilds protection.

- [x] Add failing tests for built-in migration/status and source credentials/checkpoint behavior.
- [x] Implement optional FCC/CallShield sources and gated PhoneBlock status; show evidence type/count/date quality and refresh eligibility.
- [x] Run affected hosted/UI suites serially on the existing simulator and verify normal Release compilation.

### Task 4: Acceptance, review and delivery

**Files:** Update `docs/sources.md`, the approved spec status and source validation documentation.

- [x] Run core Debug/Release, numerical reference parity, hosted/affected UI tests, packaging/site checks and normal Release compilation.
- [x] Run bounded public FCC/CallShield smoke imports; report live PhoneBlock acceptance blocked without credentials/clearance.
- [x] Dispatch one fresh-context whole-change reviewer, fix substantive findings with regression tests and re-run affected checks.
- [x] Secret-scan only intended public changes; commit focused files and push the feature branch. Keep private payloads and logs ignored.

## Execution record

The user approved the written spec and explicitly directed implementation to start.
Execution proceeds inline; detailed results and rulings are kept in the ignored
`.build/source-expansion/progress.md` while work is active.

Verified results and implementation decisions: `docs/validation/additional-call-sources.md`.
