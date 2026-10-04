"""
Spam-call reputation reference calculator.
Research proposal, 2026-10-03. NOT an empirically calibrated probability model.

Input preparation is mandatory and is not implemented here:
- normalize exact phone numbers; reject prefixes and callback-only evidence;
- deduplicate IDs and collapse mirrors into original evidence families;
- retract invalid evidence and apply confirmed assignment boundaries;
- distinguish actual event dates from report/publication dates;
- obtain legally usable evidence and validate confirmation provenance.

The score is an explainable policy index, not a probability.
This file models scoring at a successful rebuild. It cannot expire entries that
remain installed in Apple's Call Directory when background execution is absent.
"""
from __future__ import annotations
from dataclasses import dataclass
from math import exp, isfinite, log2
from typing import Mapping, Sequence
import json

@dataclass(frozen=True)
class Policy:
    identify: float
    strong_label: float
    block_association: float
    block_safety: float
    minimum_observed_days: int

POLICIES = {
    "conservative": Policy(50, 80, 90, 90, 4),
    "balanced": Policy(35, 75, 85, 75, 3),
    "aggressive": Policy(20, 65, 75, 60, 2),
}

def bounded(value: float, name: str, lo: float = 0, hi: float = 1) -> float:
    if not isfinite(value) or not lo <= value <= hi:
        raise ValueError(f"{name} must be finite and in [{lo}, {hi}]")
    return value

def source_freshness(watermark_age_days: float) -> float:
    """Use a publisher's real coverage watermark, not a local download timestamp."""
    if not isfinite(watermark_age_days) or watermark_age_days < 0:
        raise ValueError("watermark age must be finite and nonnegative")
    if watermark_age_days <= 3:
        return 1.0
    if watermark_age_days > 14:
        return 0.0
    return 2 ** (-(watermark_age_days - 3) / 7)

def family_contribution(
    daily_weighted_counts: Mapping[int, float],
    weight: float = 1.0,
    freshness: float = 1.0,
) -> float:
    """Counts are sums of q_i: 1 for an event date, .5 for report-date-only evidence."""
    bounded(weight, "weight")
    bounded(freshness, "freshness")
    total = 0.0
    for age, count in daily_weighted_counts.items():
        if not isinstance(age, int) or age < 0:
            raise ValueError("event/report age must be a nonnegative integer")
        if not isfinite(count) or count < 0:
            raise ValueError("counts must be finite and nonnegative")
        if age < 90:
            total += 2 ** (-age / 7) * min(count, 5.0)
    return min(25.0, weight * freshness * total)

def aggregate_membership_contribution(
    votes_lower_bound: float, freshness: float = 1.0
) -> float:
    """Optional preview mapping for an authorized, independently sourced aggregate.
    Not recent call counts. Does not establish observed days or origin confirmation.
    A zero-vote deletion must be processed upstream as a removal, not a positive vote.
    """
    bounded(freshness, "freshness")
    if not isfinite(votes_lower_bound) or votes_lower_bound < 0:
        raise ValueError("votes must be finite and nonnegative")
    return min(5.0, 0.5 * log2(1 + votes_lower_bound)) * freshness

@dataclass(frozen=True)
class Result:
    evidence: float
    report_index: float
    association_index: float
    block_safety_index: float
    confirmation: float
    confirmation_freshness: float
    observed_days: int
    positive_penalty: float
    uncertainty_penalty: float

def evaluate(
    independent_family_values: Sequence[float],
    *,
    confirmation: float = 0.0,
    confirmation_age_days: float = 0.0,
    confirmation_unexpired: bool = True,
    observed_days: int = 0,
    positive_penalty: float = 0.0,
    uncertainty_penalty: float = 0.0,
) -> Result:
    """confirmation: 0, .8, or 1, based on proof provenance, never on complaint count."""
    if confirmation not in (0.0, 0.8, 1.0):
        raise ValueError("confirmation must be 0, .8, or 1")
    if not isfinite(confirmation_age_days) or confirmation_age_days < 0:
        raise ValueError("confirmation age must be finite and nonnegative")
    if not isinstance(observed_days, int) or not 0 <= observed_days <= 14:
        raise ValueError("observed_days must be an integer from 0 through 14")
    bounded(positive_penalty, "positive penalty")
    bounded(uncertainty_penalty, "uncertainty penalty")
    xs = sorted(
        [bounded(x, "family value", 0, 25) for x in independent_family_values],
        reverse=True,
    )
    evidence = (xs[0] if xs else 0.0)
    evidence += .35 * (xs[1] if len(xs) >= 2 else 0.0)
    evidence += .15 * min(10.0, sum(xs[2:]))
    report_index = 100 * (1 - exp(-evidence / 8))
    if confirmation_age_days > 7 or not confirmation_unexpired:
        confirmation = 0.0
    freshness = 2 ** (-confirmation_age_days / 14) if confirmation else 0.0
    association = max(report_index, 95 * freshness) if confirmation else report_index
    persistence = min(1.0, observed_days / 4)
    block_safety = (
        association * confirmation * (.5 + .5 * persistence) * freshness
        * (1 - positive_penalty) * (1 - uncertainty_penalty)
    )
    return Result(evidence, report_index, association, block_safety, confirmation,
                  freshness, observed_days, positive_penalty, uncertainty_penalty)

def classify(
    result: Result,
    policy_name: str,
    *,
    trusted_inputs_fresh: bool = True,
    last_relevant_evidence_age_days: float = 0,
    exact_number_valid: bool = True,
    local_allow: bool = False,
    local_manual_block: bool = False,
) -> str:
    """Stateless entry thresholds. UI label hysteresis can use entry threshold - 5.
    DNO is a separate, future authorization rule, not implemented in this calculator.
    """
    if policy_name not in POLICIES:
        raise ValueError("unknown policy")
    if not isfinite(last_relevant_evidence_age_days) or last_relevant_evidence_age_days < 0:
        raise ValueError("last evidence age must be finite and nonnegative")
    if not exact_number_valid or local_allow:
        return "no_action"
    if local_manual_block:
        return "manual_block"
    p = POLICIES[policy_name]
    can_block = (
        trusted_inputs_fresh
        and result.confirmation >= .8
        and result.positive_penalty < 1
        and result.uncertainty_penalty < 1
        and result.observed_days >= p.minimum_observed_days
        and result.association_index >= p.block_association
        and result.block_safety_index >= p.block_safety
    )
    if can_block:
        return "automatic_block"
    if last_relevant_evidence_age_days > 30:
        return "no_action"
    if result.association_index >= p.strong_label:
        return "identify_many_spam_reports"
    if result.association_index >= p.identify:
        return "identify_reported_unwanted"
    return "no_action"

def worked_examples() -> dict:
    a = family_contribution(dict.fromkeys(range(7), 5))
    b = family_contribution(dict.fromkeys(range(7), 2.5))
    definitions = {
        "one_complaint": ([family_contribution({0: 1})], {"observed_days": 1}),
        "100_complaints_one_day": ([family_contribution({0: 100})],
                                  {"observed_days": 1, "uncertainty_penalty": .5}),
        "seven_days_one_family_and_any_number_of_mirrors": ([a], {"observed_days": 7}),
        "seven_days_two_families": ([a, b], {"observed_days": 7}),
        "strong_current_origin_confirmation": ([a, b],
                                              {"confirmation": 1, "observed_days": 7}),
        "one_origin_confirmation_provider": ([a, b],
                                            {"confirmation": .8, "observed_days": 7}),
        "legitimate_outgoing_or_spoof_conflict": ([a, b],
            {"confirmation": 1, "observed_days": 7, "positive_penalty": 1}),
        "all_evidence_28_days_older": (
            [family_contribution(dict.fromkeys(range(28, 35), 5)),
             family_contribution(dict.fromkeys(range(28, 35), 2.5))],
            {"confirmation": 1, "confirmation_age_days": 28}),
        "verified_assignment_reset": ([], {}),
    }
    out = {}
    for name, (values, params) in definitions.items():
        r = evaluate(values, **params)
        out[name] = {
            "family_values": values,
            "E": r.evidence, "S": r.association_index, "B": r.block_safety_index,
            "classification": {p: classify(r, p) for p in POLICIES},
        }
    return out

def run_checks() -> int:
    checks = 0
    def check(condition: bool) -> None:
        nonlocal checks
        assert condition
        checks += 1

    one = family_contribution({0: 1})
    check(abs(one - 1) < 1e-12)
    check(family_contribution({0: 100}) == 5)
    check(family_contribution({0: 1, 7: 2}) == 2)
    check(family_contribution({90: 500}) == 0)
    check(family_contribution(dict.fromkeys(range(90), 500)) == 25)
    check(source_freshness(3) == 1)
    check(source_freshness(10) == .5)
    check(source_freshness(15) == 0)
    check(evaluate([25, 25]).block_safety_index == 0)
    check(evaluate([25], confirmation=1, confirmation_age_days=8,
                   observed_days=7).block_safety_index == 0)
    check(evaluate([25], confirmation=1, confirmation_unexpired=False,
                   observed_days=7).block_safety_index == 0)
    check(evaluate([25], confirmation=1, observed_days=7,
                   positive_penalty=1).block_safety_index == 0)
    check(evaluate([25], confirmation=1, observed_days=7,
                   uncertainty_penalty=1).block_safety_index == 0)
    high = evaluate([25, 25], confirmation=1, observed_days=7)
    check(classify(high, "conservative") == "automatic_block")
    check(classify(high, "aggressive", local_allow=True) == "no_action")
    check(classify(high, "aggressive", trusted_inputs_fresh=False) != "automatic_block")
    check(classify(evaluate([25]), "balanced",
                   last_relevant_evidence_age_days=31) == "no_action")
    check(classify(evaluate([]), "conservative", local_manual_block=True) == "manual_block")
    for grade in (0, .8, 1):
        for days in (0, 1, 2, 3, 4, 7, 14):
            for age in (0, 3, 7, 8, 28):
                r = evaluate([25, 20, 10], confirmation=grade,
                             confirmation_age_days=age, observed_days=days)
                check(0 <= r.block_safety_index <= r.association_index <= 100)
    return checks

if __name__ == "__main__":
    print(json.dumps({"checks_passed": run_checks(), "examples": worked_examples()},
                     indent=2))
