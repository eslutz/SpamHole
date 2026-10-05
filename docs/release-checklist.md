# V1 release gates

This records technical release gates. A public source repository does not
establish App Store release readiness.

## Call-only scope

The user retired SMS filtering on October 4, 2026. The app has no message access
and no SMS-feed release gate. Historical SMS research is retained as retired
context, not current product requirements. FTC complaint evidence supports call
identification only; personal rules provide user-directed call blocking.

## Device verification — partially recorded

The [offline profiling harness](performance/offline-profiling.md) prepares
isolated 50,000/250,000-entry component metrics and launch capture. Static
preparation is not a physical measurement; normal-app Release traces, signing,
Contacts and actual cellular acceptance remain separate. Recorded results are in [physical validation](performance/physical-validation-2026-10-05.md); the gates below remain open beyond those specific checks.

- iPhone iOS 26 and 27: enable the Call Directory extension; receive a controlled
  call from an independently owned test caller, then verify actual behavior.
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
- Verify app/extension traffic contains no incoming numbers, contact data,
  or lookup-based requests.

## Distribution — pending

[Release automation](release-automation.md) checks packaging, configurable identity
and privacy manifests without signing credentials. Its unsigned archive check
does not establish signed distribution or physical acceptance.

- Core, hosted and UI tests pass for the intended release candidate; verify large
  text, light/dark and accessibility behavior. Automated audits do not establish
  VoiceOver speech, rotor or focus behavior.
- FTC download/import and publisher watermark were verified on-device with
  259,721 accepted records. Preserve reviewed source rights and attribution.
- Development signing, App Group access and native installation receipts were
  verified on-device. Distribution signing remains a separate gate.
- Prepare a current icon, native screenshots, public privacy/support URLs,
  collection answers, dataset attribution, commercial/age/export answers,
  metadata and a validated signed archive before distribution.
- Deliver a signed TestFlight build and verify distribution, separately from a
  successful local archive.
- User reviews metadata and final submission. Do not submit automatically.
