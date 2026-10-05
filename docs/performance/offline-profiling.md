# Offline performance capture

This provides isolated component metrics and device trace guidance. Simulator
measurements do not establish physical-device Release performance. Local
captures belong outside source control and may contain machine/device details.

## Isolated repeatable measurements

`SpamHolePerformance` is a separate opt-in Debug scheme. The ordinary `SpamHole` scheme selects the functional test classes and excludes these seven performance cases. Coverage is disabled for performance captures to reduce instrumentation overhead. Build the generated project after updating `project.yml`.

Six hosted tests cover 50,000 and 250,000 synthetic entries for saved snapshot decode/index, production pipeline rebuild/publication, and a batch of 10,000 lookup hits plus 10,000 misses. Fixture creation and initial publication are outside measured intervals. Clock, process CPU and physical-memory metrics include actor dispatch, completion synchronization and correctness assertions. XCTest records three measured repetitions after its warm-up. They are component baselines, not a UI responsiveness measurement. Synthetic neutral identification records are never treated as a vetted reputation feed.

The seventh test measures isolated empty-root application launch and verifies onboarding appears. Every launch recreates only the app's `SpamHole-UITests` temporary directory. It does not measure saved-data launch, production container hydration, background scheduling, Call Directory installation or Release launch. Do not label this as normal production launch acceptance.

Hosted fixture roots have unique `SpamHole-Performance-<UUID>` names under the test host's temporary directory. Teardown removes only the root created by that test. The harness directly calls local rebuild/load functions, never refresh/download, Contacts access or extension installation. Crash-interrupted fixture directories may remain in that isolated test container; remove only explicitly identified fixture directories, never the App Group or app installation.

The app accepts `--ui-testing` and testing color flags only in Debug. While the isolated test app is active, its idle timer is disabled to avoid auto-lock interrupting long audits. Normal use and Release retain system idle behavior. Release forces `AppModel.testing` to false and registers normal background work regardless of supplied test flags. The performance scheme has no fixture injection into a Release app.

`SpamHoleDeviceAcceptance` is a separate opt-in UI scheme that launches the normal
app container with only the Debug `--device-testing-keep-awake` flag. It captures public publisher health and
protection status, preserves existing data, and never opens Contacts. Run only
on an explicitly authorized development device. This flag changes only the active idle timer; Release ignores it. Its success does not establish
an incoming-call outcome or a successful publisher download; inspect the recorded
health and installation state separately. Keep attachments private because normal
app and system captures can contain device or personal information.

Its native block test requires an enabled extension, zero installed blocks and no
existing rule for the reserved synthetic number. It removes only its own rule.
Allow up to 15 minutes for a complete Debug FTC import: the earlier host import
took 487 seconds, so a three-minute UI wait did not establish a stalled download.

`SpamHoleReleaseProfiling` is opt-in. Select `DeviceSnapshotDiagnosticsTests` for
read-only saved-generation size/load checks. Select one `ReleaseTraceSetupTests`
method at a time to prepare Manual cadence from an observed Daily baseline, then
restore Daily immediately after capture. Unexpected cadence is preserved. These
tests access normal data and must never run in ordinary CI or on an unapproved device.

Run from the repository root, substituting the verified device UDID and a fresh output directory:

```sh
python3 scripts/profile-offline.py --destination 'platform=iOS,id=<UDID>' --output /tmp/SpamHole-device-profile-20261004
```

The runner refuses an existing output directory, runs tests serially, and retains `performance.xcresult`, `test.log`, `summary.json`, `metrics.json`, `context.json` with toolchain version and host identity, and `source-manifest.json` with SHA-256 hashes. Device model/OS, thermal and power condition still require the agent's live device inspection. `--dry-run` prints commands without writing files. `--only-testing` can select one case for a smoke run. Do not run simulator/device captures concurrently with another UI test session. No signing-team or device-registration changes are made by the runner; unresolved provisioning is a blocker to document.

## Device tracing, performed by the agent

1. Verify connected device identity, OS, available space, developer services and signing before installing anything. Record Xcode version, build configuration, source hashes, fixture size, device/OS, thermal condition and power condition with each capture. Record failures rather than infer that no device exists from a discovery timeout.
2. Run the isolated Debug metrics once, then repeat on the same device after cooldown. Keep the result bundle; don't infer peak memory or CPU time from elapsed time. `OSSignposter` intervals use subsystem `dev.ericslutz.SpamHole.Performance`, category `OfflineFixture`, and names `SavedSnapshotLoadAndIndex`, `RebuildAndPublish`, and `IndexedLookupBatch`.
3. Capture actor workload with Instruments Time Profiler/Allocations and Points of Interest, attaching to the hosted SpamHole process during the corresponding isolated test. The agent can start recording with the verified PID before starting the measured case. Installed `xctrace record --help` confirms `--device`, `--attach`, `--template`, `--output`, `--time-limit`, and `--instrument`; verify local available templates/instrument names before using them. Example recording after the process exists:

```sh
xcrun xctrace record --device '<UDID>' --attach '<PID>' --template 'Time Profiler' --time-limit 60s --output /tmp/SpamHole-offline-time.trace
```

4. For normal-app Release launch/UI traces, first assess existing app/data and prevent background refresh using the app's Manual cadence setting with prior-state restoration. Do not silently replace an existing production App Group with fixtures. If no isolated signed installation/container can be prepared safely, record normal launch profiling as blocked rather than use test bypass in Release. Cold process launch, repeated warm launch, Lookup, sheet transitions and scroll traces require app automation by the agent, not user interaction. Capture Time Profiler and SwiftUI/Hangs lanes; capture Allocations separately for retained memory after repeated operations. Restore any changed cadence after capture. Contacts-data profiling is excluded until privacy-preserving access to a known safe device dataset is available.

## Interpretation and acceptance

Do not invent absolute performance pass thresholds or claim a before/after improvement without a matching earlier trace. Compare repeats on the identical device, configuration, fixture size and workload. Investigate sustained increases larger than the run-to-run spread and any visible main-thread stalls, repeated rebuilds, growing retained allocations or device memory termination. Record sample distributions, not only the best run. Three repetitions are an initial baseline; increase repetitions when variance obscures comparison.

Pass criteria for the prepared harness are fixture integrity, successful load/rebuild/publication, correct hit/miss counts, isolated cleanup and usable metric artifacts. Physical Release acceptance still requires recorded device evidence that heavy snapshot/Contacts work stays off the UI actor, interactive operations remain responsive, and retained memory stabilizes. Simulator measurements cannot close those requirements. VoiceOver and real call behavior are separate verification items.

References: [Apple performance tests](https://developer.apple.com/documentation/xctest/performance-tests), [Apple writing and running performance tests](https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests), and [Apple Instruments memory capture guidance](https://developer.apple.com/videos/play/wwdc2022/10106/). Scheme selection uses XcodeGen's documented `selectedTests` option.

## Normal Release interaction workload

Select `ReleaseTraceSetupTests/testPrepareManualCadence`, then run
`ReleaseTraceSetupTests/testReleaseInteractionWorkload` separately. The workload
performs three process launches, followed by 20 repeated
Lookup, scrolling, and rule-sheet presentation/dismissal cycles. It uses a reserved
synthetic number and never saves a rule. It requires the observed Manual cadence
and uses bounded UI waits. Run `testRestoreDailyCadence` afterward even if capture
or workload fails; stop if the original baseline was not Daily.

Run `testReleaseWarmActivations` separately for three Home/foreground cycles.

For lower host overhead, select `testReleaseRepeatedInteractionMemory` in the
Release profiling scheme. It measures the target app with `XCTMemoryMetric`,
`XCTCPUMetric`, and `XCTClockMetric`, keeping the same process for all cycles.
`SPAMHOLE_MEMORY_REPETITIONS=3` selects the smoke test; `20` selects the full run.
XCTest performs one additional discarded warm-up cycle. Export actual metrics
from the private result bundle; a passing test without memory samples is insufficient.
Check ordered end-of-cycle physical memory and growth as well as peak memory.
These measurements do not identify individual leaked objects.

Run `testReleaseForegroundRebuildMeasurements` separately: three measured
Home/foreground workflows invoke the normal saved-data rebuild and installation.
The measured interval excludes pressing Home. Run `testReleaseSavedLaunchMeasurements`
separately for three process-launch repetitions; termination occurs after the
measurement stops. The dedicated launch metric is accepted only when present in
the exported results. Clock totals include automation and screen/idle checks;
do not label them rendering latency or a storage-cache-cold launch.

Keep captures and builds serial. Monitor test/service RSS, result size, free disk,
and host memory pressure; abort on resource limits and retain the abort reason.
Restore Daily cadence and install/launch the clean normal Release app afterward,
including after failures. Raw device result bundles remain private.

This is functional workload automation, not an XCTest timing benchmark. Record
CPU/SwiftUI and Allocations separately and verify nonempty data before treating
the recording as evidence. A saved trace or successful workload alone does not
establish performance acceptance. The read-only device diagnostics also provide
`testContactsPermissionBaselineWithoutRequestingAccess`; it reports only the
authorization enum and never requests access or enumerates contacts.

If Deferred command-line captures export empty CPU tables, try native Instruments
Time Profiler with **Immediate** recording, targeting the installed normal Release
app on the physical phone. Verify a nonempty exported `time-sample` table before
longer workloads. This recovered CPU acquisition on the October 5 test device;
it does not establish that every empty recording has the same cause.

`DeviceAcceptanceTests/testObserveControlledIncomingCall` announces observer
readiness before an agent places a separately authorized owned-caller test call.
It observes recipient call controls through InCallService and requires the agent
to hang up. Its hierarchy and screenshot attachments contain private device data
and must stay outside Git. Match the captured caller identity privately; a button
observation alone is not proof of the intended caller or blocking effectiveness.

The observer requires `SPAMHOLE_CONTROLLED_CALL_OBSERVATION=1`; the separate
block/allow cycle accepts the privately configured `SPAMHOLE_CONTROLLED_CALLER`.
Keep the configuration outside the repository. Contacts methods require
`SPAMHOLE_DEVICE_CONTACTS_TESTING=1`. Select one method at a time; never run a
whole device acceptance class with mutation flags enabled.

The Debug-only `--device-contacts-acceptance` harness runs in the normal app
process to verify effective permission independently of the Settings selection.
Selecting Full Access can leave a separate consent sheet pending; selection alone
is not proof of an effective grant. Commands are `inspect`, `create`, `modify`, and
`delete`; the UI test supplies a separately reviewed expected result. It reports
only the authorization enum and membership of three reserved numbers. A private
Application Support journal records the two fixture identities before saving.
Cleanup requires full access, validates both names against the journal, deletes
only those identities and removes the journal. Restore the authorized final
permission through native Settings afterward. If cleanup fails, stop subsequent
tests. The harness and its result overlay are excluded from Release.
