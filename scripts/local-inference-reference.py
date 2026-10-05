#!/usr/bin/env python3
"""Independent version 2 policy calculator. No caller data or network access."""
import argparse
import json
import math
from pathlib import Path

POLICIES = {"conservative": (90, 90, 4), "balanced": (85, 75, 3), "aggressive": (75, 60, 2)}
FIXTURE = Path(__file__).resolve().parent.parent / "Tests/SpamHoleCoreTests/Fixtures/local_inference_v2.json"


def family(counts, freshness=1):
    return min(25, freshness * sum(min(count, 5) * 2 ** (-age / 7)
                                   for age, count in counts.items() if 0 <= age < 90))


def evaluate(values, days, positive=0, uncertainty=0):
    if not 0 <= days <= 14 or any(not math.isfinite(v) or not 0 <= v <= 25 for v in values):
        raise ValueError("Invalid evidence")
    if any(not math.isfinite(v) or not 0 <= v <= 1 for v in (positive, uncertainty)):
        raise ValueError("Invalid penalty")
    values = sorted(values, reverse=True)
    evidence = (values[0] if values else 0) + (0.35 * values[1] if len(values) > 1 else 0)
    evidence += 0.15 * min(10, sum(values[2:]))
    report = 100 * (1 - math.exp(-evidence / 8))
    local = report * (0.5 + 0.5 * min(1, days / 4)) * (1 - positive) * (1 - uncertainty)
    return {"E": evidence, "R": report, "L": local}


def classify(result, days, policy, coverage_age=0, call_age=0):
    report, local, minimum_days = POLICIES[policy]
    return (0 <= coverage_age <= 7 and 0 <= call_age <= 7 and days >= minimum_days
            and result["R"] >= report and result["L"] >= local)


def examples():
    inputs = {
        "one_report": ([1], 1, 0, 0),
        "single_day_burst": ([5], 1, 0, 0.5),
        "three_days": ([family(dict.fromkeys(range(3), 5))], 3, 0, 0),
        "four_days": ([family(dict.fromkeys(range(4), 5))], 4, 0, 0),
        "seven_days": ([family(dict.fromkeys(range(7), 5))], 7, 0, 0),
        "two_families": ([25, 20], 7, 0, 0),
        "undated": ([25], 0, 0, 0),
        "positive_veto": ([25], 7, 1, 0),
        "uncertainty_veto": ([25], 7, 0, 1),
        "partial_uncertainty": ([25, 20], 7, 0, 0.5),
    }
    result = {}
    for name, (values, days, positive, uncertainty) in inputs.items():
        scores = evaluate(values, days, positive, uncertainty)
        result[name] = dict(values=values, days=days, positive=positive, uncertainty=uncertainty,
                            **scores, blocks={p: classify(scores, days, p) for p in POLICIES})
    return {"scoringVersion": 2, "examples": result}


def checks():
    for days in range(15):
        for positive in (0, 0.25, 1):
            for uncertainty in (0, 0.5, 1):
                scores = evaluate([25, 20, 10], days, positive, uncertainty)
                assert 0 <= scores["L"] <= scores["R"] <= 100
                c, b, a = (classify(scores, days, p) for p in POLICIES)
                assert not c or b
                assert not b or a
                assert not classify(scores, days, "aggressive", coverage_age=8)
                assert not classify(scores, days, "aggressive", call_age=8)
    assert family({0: 100}) == 5
    assert family({90: 100}) == 0
    assert examples()["examples"]["seven_days"]["blocks"]["conservative"]
    for policy, (report, local, days) in POLICIES.items():
        assert classify({"R": report, "L": local}, days, policy)
        assert not classify({"R": report - 0.001, "L": local}, days, policy)
        assert not classify({"R": report, "L": local - 0.001}, days, policy)
        assert not classify({"R": report, "L": local}, days - 1, policy)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--write-fixtures", action="store_true")
    args = parser.parse_args()
    checks()
    expected = examples()
    if args.write_fixtures:
        FIXTURE.write_text(json.dumps(expected, indent=2, sort_keys=True) + "\n")
    else:
        assert json.loads(FIXTURE.read_text()) == expected, "Version 2 fixtures differ from the independent calculator"
    print("Version 2 arithmetic, policy boundaries, expiry and nesting checks passed; fixtures match.")
