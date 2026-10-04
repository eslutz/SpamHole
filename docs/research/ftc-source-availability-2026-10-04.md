# FTC publisher availability and parser check

Updated October 4, 2026 at 16:54 UTC; clients checked October 4, 2026. **The configured FTC endpoint and a complete 24-shard refresh work on this host through SpamHole's actual Swift downloader.** Earlier Python HTTP 403 observations do not establish failure of the app's downloader. Physical iPhone downloads remain unverified. This updates the host-availability evidence in the [source contract](../sources.md); it does not clear the [release gates](../release-checklist.md).

## Verified results

| Request / check | Result |
| --- | --- |
| Configured [FTC landing page](https://www.ftc.gov/policy-notices/open-government/data-sets/do-not-call-data), actual `URLSessionSourceTransport` | HTTP 200; 991,526 bytes; same final host. |
| Actual `SourceDownloader.discoverFTCFiles` against that response | 24 same-host HTTPS CSV links. Latest displayed publication is October 1, 2026. |
| First discovered [October 1 CSV](https://www.ftc.gov/sites/default/files/DNC_Complaint_Numbers_2026-10-01.csv), actual Swift transport | HTTP 200; 1,275,411 bytes; no third-party mirror or fabricated filename. |
| Actual `SourceAdapters.parseFTC`, compiled from current repository sources | 11,089 accepted unique records; 1,204 rejected rows; coverage `2026-09-30T23:59:47Z`; all call-channel and confirmation grade zero. |
| Complete unchanged `SourceDownloader.refresh` using configured built-in source and fresh temporary SQLite store | 24 CSV shards plus landing: all 25 HTTP responses were 200; 31,565,478 total downloaded bytes including landing; 259,736 accepted/stored records; 28,054 rejected rows; coverage `2026-09-30T23:59:47Z`; persisted count matched readback; last-success present and error absent. |
| Same configured landing and CSV via Python `urllib` | HTTP 403; 453-byte HTML responses. Concrete cause unknown. |
| Publisher-owned [search.ftc.gov landing](https://search.ftc.gov/policy-notices/open-government/data-sets/do-not-call-data) and [its CSV](https://search.ftc.gov/sites/default/files/DNC_Complaint_Numbers_2026-10-01.csv) | HTTP 200 through Python and actual Swift transport; the CSV produces the same parser counts/watermark. This alternate host is unnecessary for the proven configured path. |

The eight CSV columns are `Company_Phone_Number`, `Created_Date`, `Violation_Date`, `Consumer_City`, `Consumer_State`, `Consumer_Area_Code`, `Subject`, and `Recorded_Message_Or_Robocall`. The current adapter requires the first three, fingerprints complete rows for deduplication and retains only the necessary evidence. Aggregate diagnostic parsing found 12,293 rows and usable creation dates in all rows, spanning September 30, 2026 from 00:00:22 to 23:59:47. Actual adapter rejection also applies identifier/date-order requirements, so numeric shape counts alone are not acceptance counts.

The directly fetched CSV has SHA-256 `d384b7f742083ec053359f7a8a7cdc48168c238350345bacdd1aa87ff6b421df`. Its HTTP `Last-Modified` is October 1, 2026 19:06:54 GMT. Publication and HTTP modification times differ from complaint coverage; the adapter correctly derives coverage from accepted creation dates. FTC dates without timezone remain source-local literals with the implementation's documented UTC calendar convention; this does not establish precise UTC event time.

## Rights and authority

The [FTC dataset page](https://www.ftc.gov/policy-notices/open-government/data-sets/do-not-call-data) expressly identifies these as unverified consumer reports and publishes them for industry call-blocking use. The [FTC website policy](https://www.ftc.gov/policy-notices/website-policy) says most FTC material is U.S. government work in the public domain, asks for attribution where feasible, and prohibits implying FTC endorsement. It also notes that separately copyrighted third-party material may exist on the site. Preserve dataset attribution and the current unverified call-evidence classification. These observations establish no confirmation or automatic call-blocking authority.
SpamHole is now call-only; the earlier SMS scope was retired on October 4, 2026.

## Implementation consequence and remaining acceptance

No endpoint change or production-code fix is justified by this observation. Changing only the built-in URL would leave existing installations with their persisted old URL and remove exact-match registry approval; an endpoint migration would need a deliberate store update preserving source identity, enabled state, metadata, evidence and source state. That work is unnecessary while the configured endpoint succeeds.

After the initial one-shard proof, one complete integration run used the unchanged `SourceDownloader`, `URLSessionSourceTransport` and configured built-in source with a fresh temporary SQLite store. All 24 discovered shards downloaded, parsed and merged within existing bounds, and the atomic store replacement/readback succeeded. End-to-end refresh and readback took 487 seconds on this host with the temporary harness compiled without optimization. Individual fetch, parsing and storage durations were not captured, so this timing does not identify the dominant component or establish normal-app Release performance. No second full refresh or retry was performed.

The probes preserve the existing bounded download and same-host redirect restrictions. They do not establish snapshot publication or Call Directory installation. No simulator or iPhone was used. No raw numbers or consumer fields were printed or committed. The temporary CSV, integration store and probe artifacts were removed; a cleanup check found zero remaining temporary refresh stores.

Record direct publisher fetch, complete refresh, actual source watermark, last-good-state recovery and extension installation on a physical iPhone before clearing the release gate. Distinguish the verified host Swift result from Python failure and from future cellular-network/device evidence. No specific bot protection, TLS defect, geographic restriction or phone behavior has been inferred from the 403 responses.
