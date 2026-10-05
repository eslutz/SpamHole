# Physical validation — October 5, 2026

Test device: iPhone 18 Pro Max, iOS 27.0. These are development-signed local
builds, not App Store or TestFlight acceptance. Raw logs, traces, signing settings,
device identifiers and system screenshots remain private and outside Git.

## Verified behavior

- USB installation and normal App Group startup; Wi-Fi update installation after
  unplugging USB. Long Wi-Fi test sessions were unreliable, so follow-up used USB.
- Normal FTC state: completed download/import with 259,721 accepted records and
  a September 30 publisher watermark. Current receipt: 52 identification entries.
- A reserved synthetic personal block reached iOS; removing only that rule
  restored the original zero-block baseline. No call was placed to that number.
- Release loaded the actual saved generation containing 226,265 assessments.
- Daily cadence was temporarily changed to Manual for profiling and restored.

## Fixes and regression evidence

CallKit's app callback can precede the extension's receipt write. Verification now
waits up to two seconds for the exact generation, preserving stale receipts on
timeout and respecting cancellation. Hosted delayed/stale/cancelled tests passed.

Optimized builds rejected valid labels in nested control-character predicates.
Explicit validation retains length/control checks and fixes saved JSON and binary
export reading. All 52 core tests pass in Debug and Release; valid ASCII, Unicode,
128-byte labels and invalid control/length cases are covered. CI now runs both modes.

Debug test flags prevent auto-lock while the test app is active. The normal-device
flag changes only idle behavior, retaining the real container and installer.
Release ignores test flags.

## Performance limits

Seven isolated Debug device performance cases passed on October 4. For 250,000
synthetic entries, load averaged 1.447 seconds and rebuild 9.880 seconds. The
whole-process rebuild peak was 1,156 MiB, including fixture/setup effects; no
performance acceptance threshold was configured.

A 15-second normal Release SwiftUI trace saved successfully, but CPU and SwiftUI
exports contained no samples. It is unusable performance evidence, not proof of
no hangs. Release allocation/interaction tracing, native capacity/fallback tiers,
Contacts transitions, VoiceOver speech/focus, controlled incoming calls, and
background/lock/reboot acceptance remain open.

## Follow-up agent-operated verification

- **Release interactions passed:** three process launches and 20 additional
  Lookup/scrolling/rule-sheet cycles completed on the normal saved dataset.
  The workload used a reserved synthetic lookup number and saved no rules.
  Three additional Home/foreground cycles also passed. This establishes
  functional completion, not launch latency or a memory budget.
- **Contacts transitions blocked pending baseline decision:** a read-only physical
  diagnostic verified authorization is not determined. It requested no access and
  enumerated no contacts. Transition testing cannot restore that pristine state
  using supported controls without a broader reset or reinstall; no contacts were
  created and no permissions were changed.
- **VoiceOver acceptance blocked by observation tooling:** the device query showed
  VoiceOver off. Xcode's interaction service rejected the physical destination and
  offered simulators only. Device Hub screen recording was disabled and screenshot
  capture unavailable. No reliable speech/focus observation path was established,
  so VoiceOver was left unchanged.
- **Release profiling blocked by capture tooling:** a 10-second attached SwiftUI
  recording and a 15-second launch recording with waiting-thread sampling each
  exported zero CPU rows. Recording options confirmed Time Profiler was enabled.
  Both issue stores reported a Time Mapping data-stream issue. A separate attached
  Allocations recording saved but exposed no allocation tables. The cause remains
  unconfirmed; these recordings are not accepted performance evidence.
- **Controlled calls pending destination confirmation:** Google Voice sign-in was
  available, but no recipient number was supplied. No call was placed and no real
  caller rule was changed.

The first interaction attempt failed when Apple's DTServiceHub crashed before
workload execution; the standalone retry passed. The first warm test missed a
rule-sheet presentation after application-wide scrolling. A repeat using
list-scoped scrolling and explicit toolbar readiness passed; no production code
change was inferred from that automation failure. Core regression checks passed
all 52 tests in both Debug and Release, and all 15 hosted regressions passed.
Daily refresh restoration passed. No temporary contacts or rules were created;
Contacts and VoiceOver state remained unchanged. Raw evidence remains outside Git.
