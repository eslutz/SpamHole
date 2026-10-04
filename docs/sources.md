# Source qualification and subscription contract

Checked October 3, 2026 (America/New_York). **Public release is blocked:** no reviewed free/open feed currently qualifies for automatic SMS Junk decisions. Personal SMS rules work locally. These implementation checks do not establish classification accuracy or physical-device acceptance.

## October 4 follow-up

The [dated qualification report](research/sms-feed-followup-2026-10-04.md)
rechecked publisher evidence and nine candidates. None qualifies for V1 automatic
SMS Junk: the public-release gate remains blocked and no catalog authority was
changed. Smishtank is a follow-up lead requiring a current publisher endpoint,
explicit dataset rights, exact originating identifiers, reviewed confirmation,
expiry/corrections and acceptance evidence before adapter work. No publisher
contact, purchase or registration was made. Historical observations below retain
their October 3 dates; the follow-up does not claim current payload compatibility
or measured SMS accuracy.

The [subsequent SMS options report](research/sms-filtering-options-2026-10-04.md)
found Smishtank's working bulk endpoint. Its historical data still lacks the
rights and substantive sender-confirmation lifecycle needed for automatic Junk.
The [FTC availability follow-up](research/ftc-source-availability-2026-10-04.md)
verified a complete 24-file refresh using the app's actual Swift transport,
parser and SQLite store. Earlier Python 403 observations are client-specific,
not proof that the app's downloader fails. Physical-network and extension
acceptance remain pending; the configured publisher endpoint is unchanged.

## Live findings

| Source | Observed result | Meaning and V1 decision |
| --- | --- | --- |
| [FTC daily landing page](https://www.ftc.gov/policy-notices/open-government/data-sets/do-not-call-data) | Host Python HTTPS retrieval returned HTTP 403. The web reader exposed current published links, including October 1, 2026. Following the actual link identified `/sites/default/files/DNC_Complaint_Numbers_2026-10-01.csv`; direct retrieval of that exact CSV also returned 403. No current payload compatibility is claimed. | Default call-identification adapter. The [FTC schema/API documentation](https://www.ftc.gov/developer/api/v0/endpoints/do-not-call-dnc-reported-calls-data-api) describes reported phone, creation date and alleged call date, and explicitly says reports are unverified. Complaint counts cannot grant confirmation. Prove direct downloads on an iPhone network before release. |
| [FCC metadata](https://opendata.fcc.gov/api/views/vakf-fz8e.json) and [JSON endpoint](https://opendata.fcc.gov/resource/vakf-fz8e.json) | Both returned HTTP 200. Metadata states `Public Domain U.S. Government` and links to [government-work reuse information](https://www.usa.gov/government-works). `rowsUpdatedAt` was `1791003647`, October 3, 2026 05:00:47 UTC. Inspected fields included `id`, `issue_date`, `caller_id_number`, `type_of_call_or_messge`, and distinct `advertiser_business_phone_number`. An exact `Text Message` query returned records; some lacked dates and sender numbers. | Disabled research adapter. Dataset update time is not an event date or substantive sender confirmation. Use only explicitly classified text records with exact displayed sender and usable issue date; discard missing/placeholder values and never substitute advertiser numbers. No adjudication, sender-control confirmation, expiry or correction contract was verified. |

The FCC says it [does not resolve individual unwanted-call/text complaints](https://consumercomplaints.fcc.gov/hc/en-us/articles/202752940-How-the-FCC-Handles-Your-Complaint); reports support policy/enforcement research. Public-domain status clears that dataset's observed reuse metadata, **not** its fitness for automatic filtering.

## Other candidates assessed

- [PhoneBlock integration documentation](https://github.com/haumacher/phoneblock/blob/master/CLAUDE.md) supplies bearer-authenticated bulk/delta call reputation, with monthly full downloads and daily deltas. Its [terms](https://phoneblock.net/phoneblock/usage) warn that malicious/incorrect community listings can block wanted calls. A freely redistributable confirmed SMS sender contract was not established. Excluded from V1 defaults.
- [CallShield](https://github.com/SysAdminDoc/CallShield) describes a combined call-number database, derived FTC/FCC inputs, community reports, and separate SMS content rules/corpora. Neither its MIT code license nor its signed distribution turns upstream voice complaints into independent confirmed SMS sender evidence. Excluded as a default publisher.
- [UCI SMS Spam Collection](https://archive.ics.uci.edu/dataset/228/sms+spam+collection) is a message-content evaluation corpus rather than a maintained exact-sender reputation feed. It cannot qualify a sender for Junk.
- [ComReg's Sender ID Registry](https://www.comreg.ie/industry/electronic-communications/nuisance-communications/sms-sender-id-registry/) governs registered alphanumeric SMS IDs in Ireland. It does not supply the required U.S./Canadian confirmed-spam sender feed. Registration also does not prove an incoming message's origin.

This was a targeted source review, not proof that no qualifying source exists anywhere. Reopen the gate only when a specific source is independently reviewed and satisfies every requirement below.

## Qualification and authority

Approval belongs to `SourceCatalog`, never to a source's JSON or imported settings. The registry grants FTC family weight 1 and no confirmation authority. FCC currently has weight 0 and no SMS Junk authority. Custom sources have weight 0, no independent corroboration, and no confirmation/SMS Junk authority, even if a feed supplies grades or tries to reuse a bundled source ID. Bundled approval requires matching ID, URL and format.

A future SMS approval requires a free/open dataset license allowing direct offline use, exact originating SMS sender identifiers, channel-specific substantive confirmation, reviewed confirmation methods, review/expiry timestamps, a withdrawal/correction mechanism, source lineage, and adjudicated legitimate-message evaluation. Bare complaint membership, voice-call reports, totals or self-published grades fail this gate. A maintainer must update the reviewed registry and release checklist after documenting qualification; a user toggle cannot bypass it.

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

`channel` is `call`, `sms` or `both`; role is `displayedSender`, `callback` or `advertised`. Full snapshots only: absent IDs remove prior evidence and `retractedAt` withdraws an included record. Stable IDs must be unique within a snapshot. Empty full snapshots are valid withdrawals. Accepted optional fields are `confirmationMethod`, `confirmationReviewedAt`, `confirmationExpiresAt`, `retractedAt`, `assignmentBoundaryAt`, `positivePenalty`, and `uncertaintyPenalty`. Grades are 0, 0.8 or 1 but are stripped without registry authority; penalties must be finite in [0,1]. Channel declarations must match the subscription. Prefix/range and malformed identifiers fail the whole JSON import.

The publisher watermark describes actual coverage, not the local fetch time. Dates must be valid ISO 8601 timestamps with timezones; report dates cannot exceed coverage and event dates cannot exceed report dates. JSON response limits are 32 MiB and 500,000 records. HTTP ETag/Last-Modified may avoid unchanged payloads; HTTP 304 updates successful-contact time but **does not** advance coverage or evidence age. Supplied HTTP `Content-Digest` or legacy `Digest` SHA-256 values must match downloaded bytes; unsupported/mismatched digests reject the update. Current custom schemas do not carry a signing-key contract: envelopes supplying `signature` are rejected rather than silently claiming verification. TLS success and a self-published digest do not establish sender-confirmation authority.

## Identification lists and official adapters

An identification list contains one exact telephone number per line, optionally headed `identifier`, `phone` or `number`, with CSV quoting supported. No labels, ranges or expressions. The publisher must provide HTTP `Last-Modified`; local receipt time is insufficient. Lists produce only the neutral “Listed by source” call label. They contribute no complaint score, block authority or SMS decision.

FTC ingestion discovers same-host HTTPS CSV links from the official landing page, never fabricates filenames. It reads all discovered files within limits, hashes complete original rows for stable deduplication, and discards unnecessary consumer geography/content after fingerprinting. Duplicate rows across repeated files are one item. These are daily publication shards: old rows rolling off the landing page are retained for 90 days from the observed/report day rather than misinterpreted as withdrawals. Each rebuild prunes expired rows. No unsupported FTC withdrawal protocol is invented; use an upstream correction review if a report is challenged. Coverage is the newest usable complaint creation date actually seen, not the network download timestamp.

FCC ingestion pages the public endpoint (50,000 rows per page, maximum 500,000), filters exact `Text Message` values, requires nonmissing issue dates within the recent 90-day window, and retains only exact displayed senders. Its issue date is report-date-only evidence, never an observed message time. Source-local literals remain attached to records; normalized UTC calendar indices are used for daily caps where the publisher omits a timezone and do not claim known UTC event precision.

For both official adapters, malformed schema rejects the transaction; invalid/missing exact identifiers or unusable per-row dates are counted as rejected. Status separates last attempt, last successful contact, publisher coverage and accepted count. Disabling or removing a source removes its active local contributions at the next snapshot rebuild. A successful local removal still requires successful Call Directory reload before installed call entries disappear.
