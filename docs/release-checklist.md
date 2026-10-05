# Release gates

This records technical release gates. A public source repository does not
establish App Store release readiness.

## Call-only scope

The user retired SMS filtering on October 4, 2026. The app has no message access
and no SMS-feed release gate. Historical SMS research is retained as retired
context, not current product requirements. Version 2 uses FTC complaint evidence
for local-inference automatic blocking after one-time activation; personal rules
are overrides. See [the inference policy](local-blocking.md).

## Version 2 automatic blocking — open acceptance gates

- Prove reputation-generated incoming-call suppression with no personal Block,
  then personal Allow recovery, using an isolated Release container and a matching
  installation receipt. Earlier personal-rule call tests do not clear this gate.
- Record actual FTC aggregate score distributions and block counts for all three
  policies; synthetic arithmetic and real-data counts do not establish accuracy.
- Evaluate independent, rights-cleared labelled call evidence for false positives.
  FTC complaint membership cannot serve as its own ground truth. No suitable
  labelled evaluation dataset is currently configured.
- Apple's guideline 2.5.12 requires confirmed spam. The local-inference model has
  no App Review acceptance; neither user activation nor a disclaimer establishes
  compliance. Do not represent the development build as approved for distribution.
- Preserve one-time upgrade review, source-authority boundaries, old-backup
  decoding and computed-versus-installed counts. See [version 2 validation](validation/local-blocking-v2.md).

## Device verification — partially recorded

The [offline profiling harness](performance/offline-profiling.md) prepares
isolated 50,000/250,000-entry component metrics and launch capture. Static
preparation is not a physical measurement; normal-app Release traces, signing,
Contacts and actual cellular acceptance remain separate. Recorded results are in [physical validation](performance/physical-validation-2026-10-05.md); the gates below remain open beyond those specific checks.

- iPhone iOS 27: controlled baseline delivery, personal-block suppression and
  personal-allow delivery passed on the connected device, with installation
  receipts and recipient-side observation. The original rule state was restored.
  This does not establish iOS 26 or TestFlight behavior.
- Native extension disable/re-enable recovery passed on the physical iOS 27
  device: disabled status preserved the prior receipt, re-enable completed
  installation, and cleanup restored enabled protection. Full versus incremental
  reload coverage, duplicate rejection, label changes, and other extension-error
  recovery still require separate evidence.
- Benchmark 250,000 identification and 25,000 blocking entries; exercise fallback
  tiers without losing explicit rules. Record device, OS, duration, and memory.
- Normal-data Release CPU, short Allocations, twenty-cycle app memory/CPU samples,
  and separate foreground rebuild workflow measurements are recorded. Lightweight
  XCTest metrics stayed within host resource limits. Small continued physical-
  memory growth leaves retained-memory acceptance open; isolated engine rebuild
  attribution remain open. Three-repetition responsive first-frame process launch
  samples and separate Lookup/scroll/rule-sheet workflow timings are recorded.
  Launches used warm OS caches; automation clock totals do not establish rendering
  latency. Final Daily restoration and normal Release installation/launch passed.
- Interrupt download, import, publication, and installation individually. Confirm
  atomic recovery and distinction between computed and installed generations.
- Disable background refresh, disconnect network, and age evidence. Verify stale
  warnings and removal on the next successful run/reload. Do not claim guaranteed
  Call Directory expiry.
- Contacts denied, limited, full, modification and revocation were exercised on
  the physical iOS 27 device. Fixture cache and completed installations passed;
  reputation suppression and rule precedence passed using isolated in-memory
  synthetic snapshots. Fixtures were removed, original protection preference
  restored and access left denied as authorized. Automated Full-consent tapping
  remains unverified.
- Verify app/extension traffic contains no incoming numbers, contact data,
  or lookup-based requests.

## Distribution — pending

[Release automation](release-automation.md) checks packaging, configurable identity
and privacy manifests without signing credentials. Its unsigned archive check
does not establish signed distribution or physical acceptance.

- Core, hosted and UI tests pass for the intended release candidate; verify large
  text, light/dark and accessibility behavior. Automated audits do not establish
  VoiceOver speech, rotor or focus behavior. Physical VoiceOver testing was waived
  by the user on October 5, 2026; it is not recorded as passed.
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
