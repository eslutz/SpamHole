# Physical validation — October 5, 2026

Test device: iPhone 18 Pro Max, iOS 27.0. These are development-signed local
builds, not App Store or TestFlight acceptance. Raw logs, traces, signing settings,
device identifiers and system screenshots remain private and outside Git.

## Latest acceptance status

| Item | Result | Evidence and limit |
| --- | --- | --- |
| Controlled incoming calls | Passed | Recipient-side baseline/block/allow observations and matching installation receipts; original rule state restored. |
| Contacts transitions | Passed within recorded scope | Effective denied/limited/full access, fixture-cache installation, number-change notification and revocation; snapshot precedence checked in memory. Synthetic contacts/journal removed, preference restored, final access denied. |
| Full consent automation | Unverified | Scoped handler compiles; final run had no pending consent prompt to tap. |
| Physical VoiceOver | Waived | Explicit user waiver October 5; no physical speech/focus acceptance claimed. |
| Native extension disable/re-enable | Passed | Physical native switch changed only for SpamHole; disabled status and preserved receipt verified, then enabled status and completed installation verified. Cleanup confirmed enabled protection. |
| Release performance | Incomplete | Twenty measured interaction cycles returned app memory, CPU and clock samples with low host overhead. Small continued physical-memory growth leaves retained-memory acceptance open; separate workflow timings are recorded below. |
| Final phone state | Restored | Final Daily cadence restoration passed; clean normal Release reinstalled and launched without test arguments. No test or trace remains active. |

Final opt-in device-test build passed. Shared core tests passed in Debug and
Release (52 tests each). The initial-denial navigation helper was updated to use
the verified native locators and compiled; pristine permission state was not reset
to rerun that initial prompt. The intended patch passed the secret scan and
known-private-identifier check. The sections below preserve earlier checkpoints;
this table supersedes their pending-state descriptions.

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

## Native Instruments capture recovery

On the same physical device, native Instruments Time Profiler in **Immediate**
recording mode successfully captured and exported 4,337 CPU sample rows over an
approximately 18-second launch recording. Developer Mode was already enabled,
the phone was unlocked and attached over USB, and no phone permission or security
setting was changed to obtain the trace. Previous command-line recordings used
Deferred mode and were empty. This identifies a working alternative capture path,
not a confirmed universal root cause for Deferred-mode failures.

CPU acquisition is no longer blocked. Repeated launch/interaction measurements,
SwiftUI analysis and a usable Allocations capture are still required for full
performance acceptance. The raw successful trace remains private.

The destination for controlled calls was confirmed privately. An initial call
was not accepted as baseline evidence: recipient controls were not observed, and
unknown-caller screening was active. The user disabled screening for subsequent
controlled testing. The opt-in observer now queries iOS's incoming-call UI service
and stores recipient evidence privately; call identity must be checked separately
before interpreting its result. Contacts transitions are now authorized with
access denied afterward; that authorization is not a completed test.

## Earlier controlled-call retry and Contacts progress

After the user disabled unrelated unknown-caller screening, the controlled
baseline call passed recipient-side observation. The personal-block/personal-allow
cycle also passed: each rule waited for its matching installed receipt, the
blocked call exposed no incoming-call controls during the bounded observation
window, and the allowed call displayed recipient controls for the verified owned
caller. Caller identity was checked privately against the captured recipient UI.
The test removed its temporary rule and verified the installed zero-block baseline.
These results establish the observed call behavior, not voicemail routing.

The native Contacts denial flow succeeded after waiting for the startup rebuild
to enable Settings controls. The subsequent native Settings navigation failed,
so limited/full access, modifications and revocation remain open. No synthetic
contacts were created. A read-only native Settings inspection is pending device
readiness; the authorized final permission state is denied. Raw call and permission
attachments, runtime caller configuration and destination details remain private.

## Contacts transition session

Two uniquely named reserved-number contacts were subsequently created using a
Debug-only normal-process harness and a private cleanup journal. Effective Full
access exposed both fixtures; Limited access selected only fixture A and excluded
B. The limited fixture set reached the app's protected-contact cache and a
completed installation. Modifying A's number in the settled running app exercised
the existing contact-change notification: the old number disappeared, the new
number entered protection, and installation completed. Native revocation removed
fixture protection after return/relaunch and completed installation. An isolated
in-memory reputation/rule check also passed with effective denied access.

Some Full Access attempts selected the Settings row but left a separate system
consent sheet pending. The app correctly continued to report denied access; this
does not establish an application refresh defect or a hosted-test attribution
problem. The user accepted some initial consent sheets. Automation now targets
the active consent host, including Apple's FullAccessSettingsPromptExtension,
but the final verification run encountered no pending sheet. Effective Full access
passed; an automated consent tap was not observed and is not claimed as verified.
Settings also crashed once during limited-picker navigation; a bounded retry
selected the synthetic contact successfully.

The later effective Full-access inspection passed, including the isolated
in-memory reputation/rule precedence assertions for the accessible fixtures.
Deletion then passed: only the two journal-owned synthetic contacts were removed,
the private journal was deleted, and fixture protection returned to zero. The
original disabled Contacts-protection preference and native None access were
restored by passing device tests. The final effective denied-access check passed with zero fixture membership and
contact protection disabled. No additional real caller
rules were changed.

A clean normal Release build passed and contains only the Call Directory extension,
with no test bundles. The Contacts harness/overlay strings are absent from the
Release executable. It subsequently replaced the development app on the phone; native installation
and launch both succeeded, with no test arguments.
VoiceOver remains unchanged; an alternate native capture attempt timed out, and
available capture-source metadata did not expose a verified internal speech path.
Allocations and repeated Release timing measurements remain open. Daily cadence
was not changed during this Contacts session and retains the previously verified
restoration.

## Time-bounded device handoff

On October 5, 2026, the user waived physical VoiceOver testing and requested the
phone be available within 15 minutes. VoiceOver is waived, not passed; its setting
was not changed. Cleanup, permission/preference restoration and normal Release
installation take priority. Longer Allocations and repeated timing distributions
are deferred and remain unverified. No production-readiness claim follows from
this waiver.

## Host crash and recovery

The resumed Allocations smoke runs exposed real heap statistics, and a later
attached interaction run progressed through at least nine cycles before the Mac
restarted. The temporary result bundles and traces were lost; these observations
do not close retained-memory or timing acceptance.

The host panic reports a watchdog timeout. It also records the compressor segment
limit exhausted and low swap space. An Instruments diagnostic shows its footprint
rising from approximately 334 MB to 8,265 MB on a 16 GB host. This strongly supports
profiling-related resource pressure as a contributor, without establishing the
sole cause. Raw diagnostics remain private.

Recovery restored Daily cadence successfully. Clean normal Release and Debug/
Release device-test builds passed. Core tests passed in Debug and Release (52
per mode), packaging rejection tests passed (13), and public-site validation
passed. The next device measurement was blocked by the phone locking and was
cancelled before changing cadence; no recording remains active. The clean normal
Release replacement is built but its installation is still pending device access.

Further captures must run separately from builds, discard freed allocation events,
and use a host-profiler memory cutoff. Evidence now uses an ignored private
folder that survives restart. An unrelated notification banner interrupted the
first profiled workload; a bounded dismissal/retry was added to the test harness.
Full-consent automation and physical VoiceOver are not being reopened in this
session. Native extension inspection and remaining reliability checks still need
device execution; development compile success is not device acceptance.

## Resource-bounded follow-up

Three normal-data Release launch/check/termination repetitions produced XCTest
monotonic wall-clock measurements of 3.521, 3.582 and 3.581 seconds. These include
automation and termination overhead; XCTest supplied no separate application-launch
metric. They are not cold-launch latency or a responsiveness threshold.

A saved 13.024-second attached Allocations trace was inspected in native Instruments.
The Created & Persistent view showed 82.78 MiB of heap plus anonymous VM, including
81.41 MiB of heap. Trace settings confirmed freed events were discarded. The
54 MiB recording stopped automatically when combined recorder/service RSS crossed
the 1 GiB limit (observed peak 1,072 MiB). No long recording was retried. This is
usable short allocation evidence, not a twenty-cycle retained-memory assessment.

The concurrent interaction workload completed one cycle in 18.396 seconds, then
failed when a native notification banner interrupted rule-sheet presentation.
That duration includes UI automation. The earlier twenty-cycle functional pass
remains historical evidence; this partial retry establishes no memory trend.
Daily refresh restoration passed after the interruption.

All 15 focused hosted publication/backup regressions passed on the physical device.
The unhosted core target cannot execute on a physical destination and was explicitly
skipped by Xcode; the 52-test Debug and Release core runs were host-based. A bounded
wait exposed SpamHole's native Settings switch successfully on the inspection retry.
Disable/re-enable recovery is tracked separately from read-only inspection.

The new native disable/re-enable regression compiled, but its device execution
was cancelled at locked-device preflight before any switch mutation. Its gate
remains open. The original enabled switch was observed on the read-only retry.
The clean normal Release app was reinstalled successfully after cancellation;
Daily cadence had already been restored. No test contacts or call rules were
created in this follow-up. Raw evidence remains in the ignored private directory.

## Unlocked-device recovery completion

The native disable/re-enable regression subsequently passed in 45.754 seconds.
Only SpamHole's Call Blocking & Identification switch was changed. Returning to
the app while disabled showed Disabled and pending computed changes, retaining
the prior installation-date label. Re-enabling and returning showed Enabled with
no pending generation; cleanup independently returned to the native control and
confirmed its original enabled state. This verifies the visible receipt and
foreground reload recovery, not separately instrumented incremental reload mode.
No call rules, contacts, or refresh preferences were changed by this test.

The clean normal Release app was then reinstalled and launched successfully with
no test arguments. Daily cadence remains the restored baseline. Long retained-
memory profiling and the other release gates remain open as listed above.

## Lightweight Release memory verification

The app-scoped XCTest memory/CPU approach replaced long allocation-event capture.
Three smoke repetitions returned usable samples with host test/service RSS peaking
at 253 MiB. The full run completed one discarded warm-up plus 20 measured cycles,
with host test/service RSS peaking at 159 MiB and no resource cutoff or device
memory termination. No app flags, Debug bypasses, contacts, or call-rule saves were
used. Each cycle exercised synthetic Lookup, scrolling, and rule-sheet cancellation
in the same normal Release process using the saved dataset.

| Metric | Twenty measured cycles |
| --- | --- |
| Whole interaction workflow, including automation | 18.574–19.031 s; median 18.847 s |
| Target app CPU time | 2.566–2.839 s; median 2.739 s |
| Target app peak physical memory | 108.317–115.067 MB |
| End-of-cycle physical memory | 107.334 MB first; 114.068 MB last |
| Per-cycle physical-memory delta | −0.049–3.916 MB; median +0.049 MB |

Memory rose chiefly during the first three measured cycles, then increased another
0.524 MB over the remaining 17. Those later samples include small decreases and
continued small increases. This does not establish a leak or a stable retained-
object plateau: physical footprint also reflects allocator/framework caching and
automation effects. Retained-memory acceptance remains open pending attribution
or a demonstrated plateau. No unsupported numeric memory budget was imposed.

Raw samples and resource-guard logs remain private. An initial attempt to select
the foreground rebuild accidentally repeated the interaction method; it was
cancelled after the mismatch was detected and excluded from rebuild evidence.

The corrected foreground workflow ran three measured repetitions after warm-up.
The normal foreground path invokes the saved-data rebuild and installation, with
Manual cadence preventing source downloads. Clock values were 5.716, 5.730 and
5.746 seconds; target CPU times were 3.706, 3.631 and 3.661 seconds. Target peak
physical memory was 783.699, 805.227 and 780.422 MB. End-of-interval footprints
varied substantially (633.982, 327.322 and 506.334 MB), including a negative
memory delta on the second repetition. These are whole foreground workflow
measurements, not isolated engine time or proof of main-thread stack placement.
The run completed without resource cutoff or device memory termination; host
test/service RSS peaked at 174 MiB. Separate launch and interaction phase tests
are compiled but require an unlocked device to execute.

The phone locked before the final launch/interaction suites. After waiting for an
unlock, the queued launch test and sequencing wait were cancelled without running
those methods. No device test or trace remains active. The clean normal Release
app was reinstalled; restoring the original Daily cadence and final foreground
launch remain pending an unlock. Do not start another profiling workload before
resolving that restoration or explicitly continuing the authorized Manual session.

## Final timing and restoration completion

The final unlocked-device run completed all four short timing tests and Daily
cadence restoration in one serial session. Host test/service RSS peaked at
182 MiB without a resource cutoff. Each timing has three measured repetitions
after the discarded warm-up.

| Operation | Recorded seconds |
| --- | --- |
| Responsive first-frame process launch, dedicated XCTest launch metric | 0.385, 0.399, 0.380 |
| Launch plus screen check, automation clock | 2.523, 2.533, 2.529 |
| Repeated synthetic Lookup button/result workflow | 1.821, 1.809, 1.804 |
| Rule-sheet presentation and cancellation workflow | 3.966, 3.929, 3.971 |
| Scroll up/down workflow | 2.473, 2.459, 2.444 |

Moving termination outside the measured launch interval and using the responsive
launch metric yielded actual `ApplicationFirstFramePresentationResponsive`
samples. These are process relaunches with existing saved data and warm OS caches,
not storage-cache-cold launch measurements. Other clock totals include XCTest
event synthesis and readiness checks; they do not measure rendering latency.
Foreground/warm rebuild workflow measurements remain recorded separately above.

Daily restoration passed. The clean normal Release app was installed and launched
successfully without test arguments; an initial launch-command option-order error
was corrected immediately. No temporary contacts or call rules were created.
All device tests and captures are stopped, and the phone is free to disconnect.
Small continued physical-memory growth and isolated engine/main-thread attribution
remain open; this wrap-up does not turn those limits into a performance pass.
