# Call-source expansion qualification

Checked October 5, 2026. The user selected FCC, PhoneBlock and CallShield as
additional source candidates. This report records qualification findings, not
completed adapters or authority to import every number in a publisher's list.
The current catalog still contains FTC only.

## Selected sources

| Source | Verified access and evidence | Integration requirements |
| --- | --- | --- |
| [FCC unwanted-call complaints](https://opendata.fcc.gov/Consumer/Consumer-Complaints-Data-Unwanted-Calls/vakf-fz8e) | Public Socrata JSON API responded without credentials. [Metadata](https://opendata.fcc.gov/api/views/vakf-fz8e.json) declares `USGOV_WORKS`; `rowsUpdatedAt` was October 5, 2026, 04:27:06 UTC. Caller-ID and advertiser/callback numbers are separate fields. | Implement a new voice-specific adapter, preserving rejection of the retired `fccJSON` text format. Inspect actual medium values; exclude texts and callback fields. Reject invalid/future event dates: an unfiltered maximum date returned year 9999. Publication freshness must not replace event dates. Deduplicate imports and preserve source lineage. Complaints remain unverified. |
| [PhoneBlock](https://github.com/haumacher/phoneblock/blob/master/INTEGRATIONS.md) | Documented authenticated bulk JSON and versioned deltas; integration requires publisher app registration. The [API contract](https://phoneblock.net/phoneblock/api) exposes ratings, bucketed votes and latest activity, rather than individual dated complaint events. | Confirm data-use terms with registration; the inspected [terms](https://phoneblock.net/phoneblock/usage) distinguish GPL code from noncommercial website content and do not establish an explicit database grant for SpamHole. Download directly with a user-authorized token in Keychain; no public mirror or incoming-number queries. Respect daily delta/monthly full-sync limits and zero-vote removals. Do not turn vote buckets into distinct complaint days. U.S./Canada coverage remains unmeasured. |
| [CallShield](https://github.com/SysAdminDoc/CallShield/blob/master/data/README.md) | Public signed/sharded distribution and community/maintainer records. Its [source manifest](https://github.com/SysAdminDoc/CallShield/blob/master/data/source-manifest.json) separates upstream rights, geography and evidence types. FTC/FCC are among its inputs. | Verify signatures, source rights, dated evidence, expiry and revocations. Import eligible additional community evidence without counting FTC/FCC mirrors as independent evidence. Reject prefixes, undocumented lineage and incompatible/nonredistributable inputs. Aggregate counts and first/last dates cannot supply missing distinct observed-call days. MIT code does not independently license all upstream data. |

App registration or a terms clarification would require contacting the publisher;
no publisher message, registration, account creation or subscription was made
during this qualification. No scoring weights or source approval were changed.

## Canadian candidate from the original research

The original report named the [Canadian Anti-Fraud Centre Fraud Reporting
System Dataset](https://open.canada.ca/data/dataset/6a09c998-cddb-4a22-beff-4dca67ab892f),
as an unvalidated research candidate. Live publisher metadata and the CSV header
were inspected in this follow-up:

- Licence: Open Government Licence—Canada.
- Metadata last modified: March 25, 2026. CSV resource last modified:
  October 2, 2025; published file covers January 2021–September 2025.
- The portal reports a delayed Q4 2025 update due to a system changeover.
- Fields include report ID, date received, complaint type, country/province,
  fraud category, solicitation method, demographic fields, victim count and loss.
- **No caller phone-number column exists in the inspected CSV header.**
  `Number ID` identifies the report; it is not a telephone number.

**Decision:** Do not add this statistical dataset as a caller-number feed. It
cannot produce exact-number reputation records. This finding does not establish
that no other Canadian feed exists. Canadian coverage remains an evidence gap;
international-source coverage must be measured rather than assumed from `+1`.

## Verification boundaries

Only public metadata, documentation, schema/header information and aggregate
queries are recorded here. No raw complaint numbers, private account data or
device data were added. Qualification is not a live end-to-end adapter test or
proof of automatic-block accuracy. The three selected integrations remain
pending; the Canadian candidate is not qualified.
