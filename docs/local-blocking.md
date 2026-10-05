# Version 2 local-inference policy

SpamHole generates its own call blocklist from downloaded evidence. FTC is the
initial free, reviewed source. The research's separate confirmation requirement
is replaced for production inference; version 1 remains a historical calculator.
This change does not turn FTC allegations into verified spam or establish App
Store compliance. The user activates after reviewing the local count once.

## Scores and eligibility

Retain the reference daily cap (5), seven-day half-life, 90-day retention window,
family contribution cap (25), source-freshness weighting and family aggregation.
Mirrors do not count as independent sources. Undated reports carry half weight.
Local scoring admits only enabled, catalog-approved inference sources with
publisher coverage no older than seven days. A fresh download cannot advance
publisher coverage. The latest eligible observed call must also be within seven
days; D counts distinct observed UTC dates within the preceding 14 days.

For eligible evidence, `R = 100 × (1 − exp(−E / 8))` and:

`L = R × (0.5 + 0.5 × min(1, D / 4)) × (1 − positivePenalty) × (1 − uncertaintyPenalty)`

Source freshness already affects E; there is no second freshness multiplier.
Retain the burst penalty: recent observed reports on at most two dates with at
least 80% on one date receive uncertainty penalty 0.5. Scores are inference
indices, not probabilities, caller authentication or empirically calibrated
accuracy estimates. Grade zero does not veto version 2 inference.

| Policy | Minimum R | Minimum L | Minimum D |
| --- | ---: | ---: | ---: |
| Conservative | 90 | 90 | 4 |
| Balanced | 85 | 75 | 3 |
| Aggressive | 75 | 60 | 2 |

Missing sufficient evidence, stale coverage or no recent observed event prevents
automatic blocks. Identification retains the version 1 label thresholds. Blocks
have no exit hysteresis: recomputation removes ineligible candidates immediately,
but installed entries change only after a successful iOS reload.

## Overrides and capacity

Personal Allow wins, then personal Block, then accessible protected Contacts,
then automatic inference. Contacts suppress identification and automatic blocks,
but not an explicit personal Block. The default 25,000-block capacity reserves
personal blocks before ranking automatic candidates by L descending, R descending
and number ascending. Capacity exclusions are visible and may retain labels.
Threshold eligibility is nested from Conservative through Aggressive. At capacity,
L-first ranking can replace an entry when a broader policy admits a higher-L
candidate; capped exported lists are not guaranteed to nest. Exports are sorted,
unique and identification/blocking sets are disjoint.

Activation is off when missing from legacy settings or backups. Import cannot
activate an inactive installation. Preview, computed export and receipt-verified
installation are separate states. On/off, policy, source and Contacts changes
rebuild; foreground and scheduled work recompute ageing. iOS does not provide
per-entry expiry, so no exact-time removal is promised.

## Reproducible checks

Run `swift test --jobs 2`, `swift test -c release --jobs 2`, and
`python3 -B scripts/local-inference-reference.py`. Version 2 fixtures cover
arithmetic, penalties, policy boundaries and nesting. The original
`spam_reputation_reference_20261003.py` remains unchanged for version 1 parity.

For aggregate-only evaluation, compile the standalone tool with the current core:

```sh
swiftc -O -parse-as-library -I Sources/CSQLite Sources/SpamHoleCore/*.swift \
  scripts/evaluate-local-blocking.swift -o .build/evaluate-local-blocking
.build/evaluate-local-blocking --download-ftc
```

The opt-in download uses the real downloader/parser/store and deletes its fresh
temporary database afterward. `--store-copy PATH` evaluates an already private
database copy; opening SQLite can create sidecars, so never pass the live store.
Only aggregate scores/counts are printed. Use bounded captures and serial builds;
do not commit raw evidence, private stores or device identifiers.
