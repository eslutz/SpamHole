# Offline performance capture

This provides isolated component metrics and device trace guidance. Simulator
measurements do not establish physical-device Release performance. Local
captures belong outside source control and may contain machine/device details.

## Isolated repeatable measurements

`SpamHolePerformance` is a separate opt-in Debug scheme. The ordinary `SpamHole` scheme selects the functional test classes and excludes these seven performance cases. Coverage is disabled for performance captures to reduce instrumentation overhead. Build the generated project after updating `project.yml`.

Six hosted tests cover 50,000 and 250,000 synthetic entries for saved snapshot decode/index, production pipeline rebuild/publication, and a batch of 10,000 lookup hits plus 10,000 misses. Fixture creation and initial publication are outside measured intervals. Clock, process CPU and physical-memory metrics include actor dispatch, completion synchronization and correctness assertions. XCTest records three measured repetitions after its warm-up. They are component baselines, not a UI responsiveness measurement. Synthetic neutral identification records are never treated as a vetted reputation feed.

The seventh test measures isolated empty-root application launch and verifies onboarding appears. Every launch recreates only the app's `SpamHole-UITests` temporary directory. It does not measure saved-data launch, production container hydration, background scheduling, Call Directory installation or Release launch. Do not label this as normal production launch acceptance.

Hosted fixture roots have unique `SpamHole-Performance-<UUID>` names under the test host's temporary directory. Teardown removes only the root created by that test. The harness directly calls local rebuild/load functions, never refresh/download, Contacts access or extension installation. Crash-interrupted fixture directories may remain in that isolated test container; remove only explicitly identified fixture directories, never the App Group or app installation.

The app accepts `--ui-testing` and testing color flags only in Debug. Release forces `AppModel.testing` to false and registers normal background work regardless of supplied test flags. The performance scheme has no fixture injection into a Release app.

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

Pass criteria for the prepared harness are fixture integrity, successful load/rebuild/publication, correct hit/miss counts, isolated cleanup and usable metric artifacts. Physical Release acceptance still requires recorded device evidence that heavy snapshot/Contacts work stays off the UI actor, interactive operations remain responsive, and retained memory stabilizes. Simulator measurements cannot close those requirements. VoiceOver and real call/SMS behavior are separate verification items.

References: [Apple performance tests](https://developer.apple.com/documentation/xctest/performance-tests), [Apple writing and running performance tests](https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests), and [Apple Instruments memory capture guidance](https://developer.apple.com/videos/play/wwdc2022/10106/). Scheme selection uses XcodeGen's documented `selectedTests` option.
