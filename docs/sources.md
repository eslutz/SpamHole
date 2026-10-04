# Source qualification and subscription contract

Updated October 4, 2026. SpamHole is call-only and has no message access. The
user retired SMS filtering and its feed gate on this date. Historical SMS
research remains in `docs/research/` with retirement notices, not as current
requirements. Source checks do not establish classification accuracy or
physical-device acceptance.

## FTC publisher evidence

The default source is [FTC reported unwanted calls](https://www.ftc.gov/policy-notices/open-government/data-sets/do-not-call-data).
The [October 4 availability report](research/ftc-source-availability-2026-10-04.md)
verified a complete 24-shard refresh through the actual Swift transport, parser
and SQLite store: all 25 HTTP responses were 200, 259,736 records were accepted
and stored, and persisted readback matched. Coverage was September 30, 2026
23:59:47 under the documented source-date convention. Earlier Python HTTP 403
results are client-specific and do not establish failure of the app downloader.
The configured publisher endpoint is unchanged. Physical iPhone downloads,
snapshot publication and Call Directory installation remain separate acceptance.

FTC records are unverified consumer complaints. The [FTC schema documentation](https://www.ftc.gov/developer/api/v0/endpoints/do-not-call-dnc-reported-calls-data-api)
describes reported numbers and dates; complaint counts cannot grant confirmation.
The [FTC website policy](https://www.ftc.gov/policy-notices/website-policy) describes
most FTC material as public-domain U.S. government work, requests attribution
where feasible, and forbids implying endorsement; separately copyrighted
third-party material may exist. Preserve attribution and reviewed source rights.

## Qualification and authority

Approval belongs to `SourceCatalog`, never to a source's JSON or imported
settings. The registry grants FTC family weight 1 and no confirmation or
automatic block authority. FTC evidence supports identification only. Custom
sources have weight 0, no independent corroboration, and no confirmation or
automatic block authority, even if a feed supplies grades or tries to reuse a
bundled source ID. Bundled approval requires matching ID, URL and format.

No vetted confirmation source is enabled. Any future automatic call-blocking
source must be independently reviewed for dataset rights permitting offline
use, exact originating telephone numbers, substantive confirmation methods,
review/expiry dates, withdrawals/corrections, source lineage, and legitimate-call
false-positive evaluation. Bare complaint membership, mirrors, totals or
self-published grades cannot satisfy that review. Personal rules remain explicit
user-directed decisions and take priority.

## Custom evidence JSON v1

Use a direct HTTPS URL without embedded credentials. Recognized credential query parameters (`token`, `api_key`, `key`, `access_token`, `authorization`, `password`, `client_secret`, ignoring case and underscore/hyphen variants) are rejected, including URL-encoded names. Optional bearer headers come from the containing app's separate Keychain token field; credentialed requests use redirect-controlled foreground transfers and are never placed in background-task/cache descriptors. Nonsecret query filters remain supported. Headers and URLs are never logged. Redirects must remain HTTPS on the same host and port. Downloads are bounded and a malformed import preserves the previous complete dataset.

```json
{
  "schemaVersion": 1,
  "snapshot": true,
  "publisherWatermark": "2026-10-03T00:00:00Z",
  "records": [
    {
      "id": "publisher-stable-original-record-id",
      "identifier": "+12025550100",
      "channel": "call",
      "numberRole": "displayedSender",
      "observedAt": "2026-10-01T15:00:00Z",
      "reportedAt": "2026-10-02T15:00:00Z",
      "confirmationGrade": 0
    }
  ]
}
```

`channel` must be `call`; other channel values are rejected; role is `displayedSender`, `callback` or `advertised`. Full snapshots only: absent IDs remove prior evidence and `retractedAt` withdraws an included record. Stable IDs must be unique within a snapshot. Empty full snapshots are valid withdrawals. Accepted optional fields are `confirmationMethod`, `confirmationReviewedAt`, `confirmationExpiresAt`, `retractedAt`, `assignmentBoundaryAt`, `positivePenalty`, and `uncertaintyPenalty`. Grades are 0, 0.8 or 1 but are stripped without registry authority; penalties must be finite in [0,1]. Subscriptions and all records are call-only. Prefix/range and malformed identifiers fail the whole JSON import.

The publisher watermark describes actual coverage, not the local fetch time. Dates must be valid ISO 8601 timestamps with timezones; report dates cannot exceed coverage and event dates cannot exceed report dates. JSON response limits are 32 MiB and 500,000 records. HTTP ETag/Last-Modified may avoid unchanged payloads; HTTP 304 updates successful-contact time but **does not** advance coverage or evidence age. Supplied HTTP `Content-Digest` or legacy `Digest` SHA-256 values must match downloaded bytes; unsupported/mismatched digests reject the update. Current custom schemas do not carry a signing-key contract: envelopes supplying `signature` are rejected rather than silently claiming verification. TLS success and a self-published digest do not establish sender-confirmation authority.

## Identification lists and official adapters

An identification list contains one exact telephone number per line, optionally headed `identifier`, `phone` or `number`, with CSV quoting supported. No labels, ranges or expressions. The publisher must provide HTTP `Last-Modified`; local receipt time is insufficient. Lists produce only the neutral “Listed by source” call label. They contribute no complaint score or automatic block authority.

FTC ingestion discovers same-host HTTPS CSV links from the official landing page, never fabricates filenames. It reads all discovered files within limits, hashes complete original rows for stable deduplication, and discards unnecessary consumer geography/content after fingerprinting. Duplicate rows across repeated files are one item. These are daily publication shards: old rows rolling off the landing page are retained for 90 days from the observed/report day rather than misinterpreted as withdrawals. Each rebuild prunes expired rows. No unsupported FTC withdrawal protocol is invented; use an upstream correction review if a report is challenged. Coverage is the newest usable complaint creation date actually seen, not the network download timestamp.

For the FTC adapter, malformed schema rejects the transaction; invalid/missing exact identifiers or unusable per-row dates are counted as rejected. Status separates last attempt, last successful contact, publisher coverage and accepted count. Disabling or removing a source removes its active local contributions at the next snapshot rebuild. A successful local removal still requires successful Call Directory reload before installed call entries disappear.
