# Practical SMS filtering options

Checked October 4, 2026. **Sender-only SMS filtering already exists through personal rules. Automatic community/feed Junk filtering remains blocked by data qualification, not by an absent filtering engine.** No new source qualifies on the evidence below. No source authority, release gate or implementation was changed; no account, purchase or publisher message was made.

## Recommendation and decisions

1. **Validate the existing personal-rule SMS path when a phone is available.** This is the implemented option within the current design. Agent-driven device verification remains pending and must establish delivery, extension invocation, exact-sender rules, precedence and offline behavior. No user-led manual checklist is requested. Personal rules are a user choice about an exact sender, not independently confirmed global spam evidence.
2. **Keep Smishtank as a qualification lead, with a corrected endpoint finding.** A public bulk CSV is available, but it is historical research data and does not clear rights, sender confirmation or lifecycle requirements. There is no justified production adapter task yet. The next useful external action would require separately authorized publisher contact for an explicit data grant and a current, sender-only, reviewed publication contract.
3. **If a qualifying external feed cannot be obtained, a first-party curated publisher is technically feasible but is a substantial new operational commitment.** It requires original SMS-specific evidence, rights, review, expiry, disputes and ongoing corrections, not merely republishing complaints. Alternatively, a personal-rules-first public release is a product-scope decision that would explicitly revise the existing required-feed gate. Neither decision is made by this research.

Under the currently approved V1 contract, **hold public release until a feed qualifies and device/accuracy gates pass**. A sparse, carefully qualified feed would be preferable to broad complaint-based Junk decisions; coverage must be measured and disclosed.

## Existing implementation and platform limits

[`MessageFilterExtension.swift`](../../Extensions/MessageFilter/MessageFilterExtension.swift) reads only `queryRequest.sender`, loads the local App Group snapshot and returns allow/Junk or `.none`. It does not inspect a message body, record incoming messages or defer to a server. [`SnapshotBuilder.swift`](../../Sources/SpamHoleCore/SnapshotBuilder.swift) builds exact personal rules, applies allow precedence and requires reviewed SMS confirmation authority plus current evidence for automatic Junk. [`SourceCatalog.swift`](../../Sources/SpamHoleCore/SourceCatalog.swift) grants no current source that authority; custom imports cannot grant it themselves.

Apple documents local classification as supported, and its API documentation describes unknown-sender SMS/MMS filtering, excluding Contacts senders and iMessage. Apple also says the extension cannot access the network directly or write shared containers. Its current iPhone user guide mentions SMS/MMS/RCS text filtering, so RCS behavior should be tested separately before claiming support. SpamHole's current supported claim remains SMS; this report does not expand it. [Apple IdentityLookup](https://developer.apple.com/documentation/identitylookup/sms-and-mms-message-filtering), [iOS 26 filtering guide](https://support.apple.com/en-gb/guide/iphone/iph203ab0be4/26/ios/26).

Exact displayed-sender matching cannot authenticate origin. NCSC explains that telecom systems cannot reliably identify who originated a call or SMS; this limits any sender-only filter's precision and recall even when its download and matching are correct. A legitimate identifier can be impersonated and a campaign can use fresh identifiers. This is an inherent limitation to evaluate, not a reason to silently add content analysis. [NCSC guidance](https://www.ncsc.gov.uk/guidance/business-communications-sms-and-telephone-best-practice).

## New direct-source findings

### Smishtank: bulk endpoint found, qualification still fails

The publisher's current [public application asset](https://smishtank.com/static/js/main.7167f1c0.js) links [analysisdataset.csv](https://smishtank.com/analysisdataset.csv). Direct unauthenticated HTTPS retrieval returned HTTP 200, `text/csv`, 731,902 bytes, `Last-Modified: Sat, 16 May 2026 12:52:49 GMT`; SHA-256 `55dd9a19d48b51a86acd35b97cfa50f77453488434498521ce1f6ba5d52bef15`. This corrects the earlier endpoint gap: `/dataset` returning 404 does not imply the bulk CSV is unavailable.

Diagnostic parsing found 1,062 rows; `Sender`, `SenderType`, `messageid` and `timeReceived` fields, with no per-sender review, expiry or retraction fields. Sender is nonempty in 973 rows. Receipt dates parse as March 31, 2022–December 13, 2023, without timezone. HTTP modification time is not evidence freshness. Sender types include phone, short code and email-to-text; some identifiers are missing. Numeric shape alone does not prove exact origin. The bytes are not valid UTF-8; Latin-1 was used only for metadata diagnostics, not production ingestion. No raw sender values or message content were persisted.

Publisher [terms](https://smishtank.com/terms), inspected through its served application, reserve content removal/editing; no explicit free/open dataset grant or machine-readable sender correction contract was found. Citation instructions do not supply such a grant. **Not qualified.**

### HuShield: relevant offline design, not a qualified feed

The [publisher README](https://github.com/Hushield/hushield/blob/main/README.md) describes offline SMS classification, authenticated bulk/delta blocklist downloads, removal tombstones and decaying community votes. Its [code license](https://github.com/Hushield/hushield/blob/main/LICENSE) is Apache-2.0. However, its documented model votes on E.164 numbers without establishing SMS-specific originating-sender adjudication, and its seed path accepts FTC/FCC data. App Attest verifies a reporting device; it does not verify a report or message origin. A code license does not by itself establish rights to the hosted database. The publisher explicitly says actual offline SMS classification has not yet been physically verified. **Not qualified; possible lifecycle implementation reference only.** No attestation/account setup or protected payload fetch was attempted.

### DNO and sender registries: useful narrower leads, not substitute spam feeds

FCC's [published text-blocking guide](https://docs.fcc.gov/public/attachments/DA-24-859A1_Rcd.pdf) describes carrier-level blocking of texts from reasonable Do-Not-Originate lists, including subscriber-requested non-originating numbers, with a correction contact. This is a potentially stronger evidence model for a narrow anti-spoof list than complaints: a number owner attests that the number does not originate texts. It is not a verified, openly licensed downloadable SMS dataset for SpamHole. Carrier rules do not grant an app data access or source authority. No qualifying publisher endpoint was found in this review.

Ofcom's [DNO service](https://www.ofcom.org.uk/phones-and-broadband/scam-calls-and-messages/do-not-originate) describes inbound-only **voice** numbers shared with providers and some blocking services. Do not infer that a voice-only number never sends SMS. Registered alphanumeric sender lists likewise do not authenticate an incoming message or establish that an unregistered sender is spam. A dedicated, licensed **SMS** DNO list would need separate source/policy review before use.

## Feasible future publisher contract

An external or first-party feed must provide exact displayed sender and country/type context, stable evidence IDs, dated SMS-specific substantive confirmation and reviewed methods, explicit free/open offline-use rights, actual coverage watermarks, review/expiry dates, and authoritative corrections/removals. Publish bounded full snapshots directly over HTTPS; current custom ingestion supports complete-snapshot withdrawals but not arbitrary delta formats. Avoid message bodies, recipient data and credentials in the published payload. A publisher transformation does not cure missing upstream rights or authority.

For a first-party program, distinguish a controlled observation from proof of sender control and separate spam-specific originating numbers from impersonated legitimate identifiers. Independent human review, documented evidence handling, dispute ownership and an expiry policy must exist before catalog approval. No collection or hosting program was started here.

Before approval, evaluate adjudicated legitimate and unwanted senders using time-separated evidence, recording precision, recall, sample sizes, zero false Junk in the designated legitimate set and correction-to-device latency. Include legitimate OTP/appointment senders, reassigned numbers and spoofed identities. Report narrow coverage honestly; zero observed false positives does not establish zero future error.

## Options that do not solve the current gate

- FCC complaints, voice reputation, crowd-vote thresholds and self-declared confirmation grades do not become confirmed SMS origin evidence through aggregation.
- Message-text/URL corpora and on-device ML may support other products, but conflict with this approved sender-only scope. Offline execution alone does not satisfy it.
- Hashed incoming-number lookups still query a server about incoming identifiers and conflict with the no-lookup boundary.
- Junking every unknown sender would misclassify wanted messages and abandon fail-open matching. Apple's unknown-sender screening is an optional system feature, not SpamHole reputation data.
- Personal-rule backup/import supports the same user-authored rules; importing an unreviewed community list as purported personal decisions would bypass the authority boundary.

The [earlier nine-candidate review](sms-feed-followup-2026-10-04.md) remains useful for other exclusions; its Smishtank endpoint gap is superseded by the direct CSV observation above. This targeted search cannot establish that no qualifying publisher exists anywhere.
