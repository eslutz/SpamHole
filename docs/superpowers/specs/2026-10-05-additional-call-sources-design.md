# Additional call sources and shared normalization

Date: October 5, 2026.
Status: written specification approved; implementation and validation recorded in
`docs/validation/additional-call-sources.md`. PhoneBlock live activation remains gated.

## Outcome and boundaries

Integrate FCC, PhoneBlock and CallShield alongside FTC. Each adapter validates
and normalizes publisher data before the shared reputation algorithm runs.
The iPhone continues to download datasets, calculate scores and install exact
Call Directory entries locally. No incoming-number lookup, message access,
public data mirror or submission of user reports is added.

The user approved retaining existing policy thresholds and distinguishing
aggregate reputation from individual dated reports. Aggregate-only evidence
cannot satisfy the existing observed-call persistence requirement. Personal
Allow, personal Block and accessible protected Contacts retain their current
precedence. Activation, capacity selection and last-good installation behavior
remain in force.

## Architecture

Keep the existing downloader, SQLite store and snapshot pipeline. Add three
official adapter formats without reusing the retired `fccJSON` text format.
The app-owned catalog defines permitted origins, source families, rights status,
weights and local-inference eligibility. Publisher payloads and imported settings
cannot grant those permissions.

The pipeline is:

1. Fetch bounded publisher responses and required metadata.
2. Verify the applicable transport, signature and schema contracts.
3. Normalize exact identifiers, dates, evidence types and correction actions.
4. Atomically commit normalized evidence with its source checkpoint.
5. Apply source-family deduplication and expiry.
6. Calculate shared scores and policy eligibility, then export/install a snapshot.

Do not import a publisher's computed score as SpamHole's score. Separate adapters
permit direct offline use and corrections without operating another service.

## Normalized evidence contract

Extend the shared evidence model with backward-compatible optional metadata for
evidence kind, aggregate vote floor, category, activity date, expiry and original
publisher identity. Existing records decode as individual reports with their
existing behavior. Store publisher literals where needed to explain date quality.

An individual report has a stable original record ID, exact displayed caller
number, source family, report/publication date and an optional actual observed
call date. An aggregate has one stable record per number and originating family,
a vote floor or membership assertion, category and optional latest activity;
it has **no observed-call date** unless a separate event actually supplies one.
A review date, first/last-seen pair or bucketed count is not a sequence of calls.

Normalize phone numbers using country-aware metadata. U.S./Canadian national
forms use NANP rules. Explicit international numbers retain their country code;
German and Italian PhoneBlock numbers must not be coerced to `+1`. Reject
extensions, short codes, ranges, prefixes and malformed identifiers. Validation
establishes numbering structure, not assignment or caller authenticity.

Validate calendar dates strictly, reject future/impossible values and preserve
timezone uncertainty. Calendar-only publisher dates use a documented UTC day
bucket without pretending to know the local call time. Network receipt time and
HTTP 304 must never make old evidence new. Discard consumer location, free-text
descriptions and other fields not needed for scoring or record identity.

Unknown categories, missing lineage and unusable dates never acquire invented
values. A changed required schema rejects the transaction; isolated invalid rows
are counted and excluded under the adapter's documented rules.

## Scoring behavior

Keep the existing `ReputationEngine` and `LocalInferenceEngine` formulas,
thresholds, daily/family caps and decay. Original FCC complaints use family weight
1. Reviewed additional community evidence uses weight 0.5, as proposed in the
original research. These weights are policy choices, not measured accuracy.

Use the existing `aggregateMembershipContribution` function for documented vote
floors: `min(5, 0.5 * log2(1 + votes))`, multiplied by reviewed family weight,
source freshness and seven-day activity decay when usable activity is supplied.
An undated membership assertion can provide a neutral source identification
label but contributes no scored, fresh blocking evidence. For a number/family
with both event and aggregate representations, use the stronger contribution
rather than adding the same reports twice. Repeated aggregate snapshots replace
the record instead of accumulating new evidence.

Only actual observed-call days increment persistence or establish the recent-call
requirement. Community aggregate votes, maintainer review dates and refresh dates
contribute zero observed days. They can supplement a score supported by genuine
dated calls, but cannot independently authorize automatic blocking. No adapter
grants origin-confirmation authority based on a complaint count or review label.

## FCC adapter

Use dataset `vakf-fz8e` through the publisher's HTTPS Socrata JSON endpoint.
Import the existing 90-day evidence window with deterministic, bounded paging;
require completion before replacing the source dataset. Detect a changing dataset
during paging and retain the previous import instead of installing a partial list.

Allow only inspected voice classifications: `Abandoned Calls`, `Autodialed Live
Voice Call`, `Live Voice` and `Prerecorded Voice`. Exclude text, email, unknown
and blank classifications. Use `caller_id_number` exclusively; never substitute
the advertiser/business phone number. Stable IDs come from FCC Ticket ID.

FCC describes `issue_date` as the date the consumer says the violation occurred;
normalize it as the alleged observed-call day. It does not supply a separate
complaint-receipt timestamp in this schema: preserve that absence explicitly
instead of claiming a real report date. Store required publication provenance
separately, using valid publisher metadata. Reject invalid future dates, including
the year-9999 values observed during qualification. A completed source refresh
does not validate any allegation or prove that the caller owns the displayed ID.

## PhoneBlock adapter

Use authenticated bulk JSON and `since=<version>` deltas from the publisher.
Build the adapter, synthetic tests and credential/status interface without
claiming that app registration or database-use clearance has occurred. The source
starts disabled and cannot activate until its app-owned rights/access gate is
cleared and the user supplies authorized credentials. Tokens remain in Keychain,
excluded from settings, backups, logs and public files.

Preserve category, documented vote bucket and `lastActivity` milliseconds.
Zero votes mean removal, not legitimate-number confirmation. Unknown ratings or
unsupported vote values are not silently treated as spam. Aggregate records use
the normalization/scoring contract above; latest activity is not an observed call.

Commit delta changes and the new version in the same SQLite transaction. Apply
at most one delta opportunity per day and one full-sync opportunity per month,
with persisted scheduling/backoff and jitter. Manual refresh cannot bypass these
limits. Failed or incompatible updates retain the prior version and dataset;
a required full resync waits for its permitted opportunity. Source removal clears
credentials and checkpoint state. A token rotation invalidates the authenticated
dataset/checkpoint association before another account can reuse it.

Do not query individual numbers, import PhoneBlock personal lists, add report
submission, or automatically contact/register with the publisher in this scope.

## CallShield adapter

Use the publisher's signed manifest and content-addressed exact-number shards.
Verify signatures against reviewed, bundled public keys and verify every shard's
digest and declared size/count. Do not trust a key supplied in the downloaded
manifest. Reject incompatible manifest versions, path traversal, rollback and
cross-origin resource changes; commit only a complete verified generation.
Conditional requests may reuse verified cached shards, not unvalidated bytes.

Use an app-owned allowlist of reviewed community/maintainer evidence types and
their permitted rights. The upstream manifest supplies provenance to validate,
not authority to expand that allowlist. Ignore imported FTC/FCC evidence in this
adapter because SpamHole obtains those families directly. Never count the
CallShield aggregate database snapshot itself as another independent report.
Exclude restricted, unknown-provenance and prefix/range inputs.

Import genuinely dated event records where their schema establishes an observed
call; otherwise retain aggregate or review semantics. Preserve expiries and
revocations and remove absent evidence after a verified authoritative full
snapshot. Where the publisher's feed uses `cleared`, empty output with
`cleared: false` retains prior evidence; deliberate empty output with
`cleared: true` applies its documented withdrawals. A review alone does not
establish actual call dates or substantive origin confirmation.

## App integration and recovery

Existing installations receive missing built-in entries without reenabling a
source the user disabled. FTC keeps its existing state. FCC and CallShield become
available as optional sources; activation requires their reviewed contracts to
pass. PhoneBlock explicitly displays its access/rights gate rather than a generic
download failure. Source detail shows event versus aggregate evidence, rejected
counts, coverage/activity provenance, last successful contact and next permitted
refresh. Lookup explains contributions without portraying votes as observed days.

Every failed download, cancellation, validation or transaction preserves the
complete previous source dataset. Failed snapshot installation preserves the last
installed generation. Disable/removal excludes the source at rebuild; the UI
continues to distinguish generated protection from protection installed by iOS.

## Validation and delivery

Add synthetic fixtures and meaningful tests for:

- Cross-source representations of the same exact number and international numbers.
- FCC classification filtering, callback exclusion, pagination completion,
  changed datasets, duplicate IDs, future dates and missing dates.
- PhoneBlock buckets, ratings, full/delta updates, zero-vote removals, rollback,
  credential changes, rate limits and transactional checkpoint recovery.
- CallShield signatures, digests, paths, versions, lineage, duplicated upstream
  evidence, expiry, revocation and both empty-feed meanings.
- Aggregate votes not creating observed days; contributions reaching the shared
  scorer; policy thresholds and override precedence remaining unchanged.
- Backward-compatible stored data, source activation/status and last-good recovery.

Run core Debug/Release and reference-model parity tests, hosted tests, affected
UI tests and a normal Release build serially within the Mac's disk/RAM budget.
Perform bounded live public-feed checks separately from synthetic parser tests;
PhoneBlock live acceptance remains blocked until authorized access and rights
are established. Simulator success does not prove physical call suppression.

Update source documentation and sanitized validation findings. Secret-scan intended
changes, commit focused files and push the feature branch. Do not change phone
settings, Contacts or personal rules during these source-integration checks.

## Evidence

Qualification and publisher links are recorded in
[call-source-expansion-2026-10-05.md](../../research/call-source-expansion-2026-10-05.md).
The Canadian Anti-Fraud Centre CSV contains no caller-number field and remains
excluded. Source integration does not establish comprehensive Canadian coverage,
labelled accuracy, App Store acceptance or completion of existing release gates.
