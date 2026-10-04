# V1 release gates

This records technical release gates. A public source repository does not
establish App Store release readiness.

## Required free/open SMS feed — BLOCKED

No reviewed source currently authorizes automatic SMS sender filtering.
FCC's `Text Message` records are complaints, not confirmed spam originators.
Voice complaints must never become SMS Junk decisions.

The [October 4 qualification follow-up](research/sms-feed-followup-2026-10-04.md)
rechecked nine candidates and found none qualified. Smishtank is the strongest
qualification lead, with current endpoint, rights, exact-identifier and lifecycle
evidence still missing. No source was promoted to trusted authority.

The [SMS options research](research/sms-filtering-options-2026-10-04.md) subsequently
found Smishtank's working bulk CSV endpoint. Its historical records, rights and
sender-confirmation lifecycle still do not qualify it. The missing-endpoint
finding is superseded; the source authority and release gate remain unchanged.

A qualifying source must expose exact SMS sender identifiers, current SMS-specific
confirmation evidence and methodology, dated coverage, an explicit free/open
license permitting on-device processing, and withdrawals/corrections. Its
publisher and provenance must be reviewed before it is added to the trusted
catalog. Self-declared grades in custom subscriptions do not count.

Validate against an adjudicated, time-separated SMS acceptance set. Report
precision, recall, legitimate-message false positives, sample size, and correction
latency separately. Public release requires no false Junk decisions in the
designated legitimate-message set; this sample result does not establish zero
real-world error. If no feed qualifies, hold release.

## Device verification — pending until recorded

The [offline profiling harness](performance/offline-profiling.md) prepares
isolated 50,000/250,000-entry component metrics and launch capture. Static
preparation is not a physical measurement; normal-app Release traces, signing,
Contacts and actual cellular acceptance remain separate. Device-only behavior remains unverified until recorded.

- iPhone iOS 26 and 27: enable each extension separately; receive a controlled
  call/SMS from an independently owned test sender, then verify actual behavior.
- Full and incremental call reloads, duplicate rejection, label changes, rules,
  extension disabled/error recovery, and readable installation receipts.
- Benchmark 250,000 identification and 25,000 blocking entries; exercise fallback
  tiers without losing explicit rules. Record device, OS, duration, and memory.
- Interrupt download, import, publication, and installation individually. Confirm
  atomic recovery and distinction between computed and installed generations.
- Disable background refresh, disconnect network, and age evidence. Verify stale
  warnings and removal on the next successful run/reload. Do not claim guaranteed
  Call Directory expiry.
- Contacts denied, limited, granted, modified, and revoked; manual rules remain
  effective with the documented precedence.
- SMS phone/short-code/alphanumeric matching, allow overrides, expired feed
  evidence, missing snapshots, and wanted messages from spoofed senders.
- Verify app/extension traffic contains no incoming numbers, sender/body data,
  contact data, or lookup-based requests.

## Distribution — pending

[Release automation](release-automation.md) checks packaging, configurable identity
and privacy manifests without signing credentials. Its unsigned archive check
does not establish signed distribution or physical acceptance.

- Core, hosted and UI tests pass for the intended release candidate; verify large
  text, light/dark and accessibility behavior. Automated audits do not establish
  VoiceOver speech, rotor or focus behavior.
- FTC CSV access, parser compatibility, publisher watermarks and source rights
  are demonstrated on-device. Optional FCC rights/freshness must be established.
- Choose signing team, verify App Group access on-device and extension receipts.
- Prepare a current icon, native screenshots, public privacy/support URLs,
  collection answers, dataset attribution, commercial/age/export answers,
  metadata and a validated signed archive before distribution.
- Deliver a signed TestFlight build and verify distribution, separately from a
  successful local archive.
- User reviews metadata and final submission. Do not submit automatically.
