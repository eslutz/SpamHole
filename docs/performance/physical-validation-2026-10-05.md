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
