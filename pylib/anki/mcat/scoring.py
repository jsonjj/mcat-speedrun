# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Transparent, AI-off scoring for MCAT Speedrun.

The NUMBERS all come from the shared Rust engine (`mcat_core`, called via
`col._backend.mcat_scores`) — the exact same code the iOS app runs — so both
apps are guaranteed identical. This module only builds the engine's inputs
(combined study aggregate + static coverage) and shapes the engine's output into
the transparent, evidence-first dict the desktop frontend expects.

- Memory:      recall accuracy on graded memory reviews.
- Performance: first-answer correctness with a Wilson interval.
- Readiness:   performance mapped onto 118-132 and summed, with strict
               abstention (or a low-confidence diagnostic estimate).
"""

from __future__ import annotations

import json
import time
from typing import TYPE_CHECKING, Any

from anki.mcat import content, schema, store
from anki.mcat.taxonomy import load_taxonomy

if TYPE_CHECKING:
    import anki.collection

# Kept only for the readiness confidence label + dev override (the numeric gates
# themselves live in the Rust engine).
SECTION_COVERAGE_MIN = 0.40
MIN_PERF_SETS_PER_SECTION = 2
OVERALL_MIN_GRADED_REVIEWS = 100
OVERALL_MIN_PERF_ATTEMPTS = 40
SECTION_MIN, SECTION_MAX = 118, 132
TOTAL_MIN, TOTAL_MAX = 472, 528


def compute_scores(col: anki.collection.Collection) -> dict[str, Any]:
    """Compute memory/performance/readiness for the whole exam and per section."""
    override = store.get_dev_scores(col)
    if override and store.get_profile(col).get("is_dev"):
        return _dev_override_scores(override)

    profile = store.get_profile(col)
    taxonomy = load_taxonomy()
    _mem_topics, perf_topics = content.pack_topic_sets()

    # Combined engine log = this device's log + the other device's, merged by the
    # engine's replay-union. Both apps score from the same merged log, so scores
    # and per-card state reflect combined study across devices.
    combined_json = col._backend.mcat_merge(
        state_json=json.dumps(store.get_mcat_log(col)),
        other_json=json.dumps(store.get_remote_mcat_log(col)),
    )
    agg = _aggregate_from_log(json.loads(combined_json))

    coverage: dict[str, list[int]] = {}
    coverage_pct: dict[str, float] = {}
    for section in schema.SECTIONS:
        covered, total, pct = _coverage(section, perf_topics, taxonomy)
        coverage[section] = [covered, total]
        coverage_pct[section] = pct

    # One engine, one set of numbers: the Rust engine computes everything from the
    # merged log; Python only shapes the transparent dict. The generated bridge
    # unwraps the single-field response to the string itself.
    engine = json.loads(
        col._backend.mcat_scores(
            state_json=combined_json,
            coverage_json=json.dumps(coverage),
            external_json="{}",
            diagnostic_kind=profile.get("diagnostic_kind") or "",
        )
    )

    sections: dict[str, Any] = {}
    for section in schema.SECTIONS:
        a = agg[section]
        es = engine["sections"][section]
        sections[section] = {
            "name": schema.SECTION_NAMES[section],
            "coverage_pct": round(coverage_pct[section], 3),
            "covered_topics": coverage[section][0],
            "total_topics": coverage[section][1],
            "memory": _shape_memory(es["memory"], a),
            "performance": _shape_performance(es["performance"], a),
            "readiness": _shape_section_readiness(es["readiness"], a, coverage_pct[section]),
        }

    total_reviews = sum(a["reviews"] for a in agg.values())
    total_attempts = sum(a["attempts"] for a in agg.values())
    total_correct = sum(a["correct"] for a in agg.values())
    total_sets = sum(a["sets"] for a in agg.values())

    return {
        "generated_at": int(time.time()),
        "ai_enabled": False,
        "memory": _shape_overall_memory(engine["memory"], total_reviews),
        "performance": _shape_overall_performance(
            engine["performance"], total_correct, total_attempts, total_sets
        ),
        "readiness": _shape_overall_readiness(
            engine["readiness"],
            engine["sections"],
            total_attempts,
            total_reviews,
            agg,
            coverage_pct,
        ),
        "sections": sections,
    }


# Engine inputs
#############################################################################


def _aggregate_from_log(log: dict[str, Any]) -> dict[str, dict[str, int]]:
    """Per-section {attempts, correct, sets, reviews, reviewsCorrect} derived from
    the merged engine log — used only for the transparent evidence text."""
    out: dict[str, dict[str, int]] = {
        sec: {"attempts": 0, "correct": 0, "sets": 0, "reviews": 0, "reviewsCorrect": 0}
        for sec in schema.SECTIONS
    }
    batches: dict[str, set[str]] = {sec: set() for sec in schema.SECTIONS}
    for a in log.get("attempts", []):
        sec = a.get("section")
        if sec not in out:
            continue
        out[sec]["attempts"] += 1
        if a.get("first_correct"):
            out[sec]["correct"] += 1
        bid = a.get("batch_id")
        if bid:
            batches[sec].add(bid)
    for r in log.get("reviews", []):
        sec = r.get("section")
        if sec not in out:
            continue
        out[sec]["reviews"] += 1
        if int(r.get("rating", 0)) >= 3:
            out[sec]["reviewsCorrect"] += 1
    for sec in out:
        out[sec]["sets"] = len(batches[sec])
    return out


def _coverage(
    section: str,
    perf_topics: dict[str, set[str]],
    taxonomy: Any,
) -> tuple[int, int, float]:
    """Coverage = the share of the section's outline (taxonomy topics ∪ topics
    that have a practice item) that has a performance item. Performance drives
    readiness, and this keeps coverage stable regardless of the flashcard set."""
    tax = set(taxonomy.topic_ids(section))
    perf = perf_topics.get(section, set())
    universe = tax | perf
    total = max(1, len(universe))
    covered = sum(1 for topic in universe if topic in perf)
    return covered, total, covered / total


# Shaping the engine output into the frontend dict
#############################################################################


def _shape_memory(eb: dict[str, Any], a: dict[str, int]) -> dict[str, Any]:
    if eb.get("abstained"):
        return _block(
            abstained=True,
            reason="No graded memory reviews yet in this section.",
            coverage_pct=eb.get("coverage_pct", 0.0),
            evidence="No graded memory reviews.",
            missing="Review some memory cards to estimate recall.",
            next_action="Start a short memory block.",
        )
    reviews = a["reviews"]
    return _block(
        abstained=False,
        point=eb.get("point"),
        low=eb.get("low"),
        high=eb.get("high"),
        unit="percent_recall",
        coverage_pct=eb.get("coverage_pct", 0.0),
        confidence=_confidence_from_count(reviews, low=10, medium=40, high=120),
        evidence=f"{a['reviewsCorrect']}/{reviews} memory reviews recalled.",
        missing=None if reviews >= 80 else "More reviews would tighten this.",
        next_action="Keep maintenance reviews on weak topics.",
    )


def _shape_performance(eb: dict[str, Any], a: dict[str, int]) -> dict[str, Any]:
    if eb.get("abstained"):
        return _block(
            abstained=True,
            reason="No performance attempts yet in this section.",
            coverage_pct=eb.get("coverage_pct", 0.0),
            evidence="No exam-style attempts.",
            missing="Answer performance questions to estimate application.",
            next_action="Do a performance set in this section.",
        )
    n = a["attempts"]
    return _block(
        abstained=False,
        point=eb.get("point"),
        low=eb.get("low"),
        high=eb.get("high"),
        unit="percent_correct",
        coverage_pct=eb.get("coverage_pct", 0.0),
        confidence=_confidence_from_count(n, low=5, medium=20, high=60),
        evidence=f"{a['correct']}/{n} first-answer correct over {a['sets']} set(s).",
        missing=None if n >= 20 else "More attempts would tighten this.",
        next_action="Keep doing varied performance sets.",
    )


def _shape_section_readiness(
    eb: dict[str, Any], a: dict[str, int], cov: float
) -> dict[str, Any]:
    if eb.get("abstained"):
        if cov < SECTION_COVERAGE_MIN:
            reason = (
                f"Coverage {cov:.0%} is below the {SECTION_COVERAGE_MIN:.0%} needed "
                "(each counted topic needs a memory and a performance item)."
            )
            evidence = "Insufficient topic coverage."
            missing = "Add memory and performance items across more topics."
            next_action = "Broaden coverage in this section."
        else:
            reason = (
                f"Fewer than {MIN_PERF_SETS_PER_SECTION} performance sets in this section."
            )
            evidence = f"{a['attempts']} attempt(s), {a['sets']} set(s)."
            missing = "Complete more performance sets."
            next_action = "Do another performance set here."
        return _block(
            abstained=True,
            reason=reason,
            coverage_pct=eb.get("coverage_pct", 0.0),
            evidence=evidence,
            missing=missing,
            next_action=next_action,
        )
    return _block(
        abstained=False,
        point=eb.get("point"),
        low=eb.get("low"),
        high=eb.get("high"),
        unit="section_score",
        coverage_pct=eb.get("coverage_pct", 0.0),
        confidence=_downgrade(_confidence_from_count(a["attempts"], low=5, medium=20, high=60)),
        evidence=f"Based on {a['attempts']} performance attempt(s); coverage {cov:.0%}.",
        missing="A full-length section would sharpen this.",
        next_action="Mix in timed sets to confirm pacing.",
    )


def _shape_overall_memory(eb: dict[str, Any], total_reviews: int) -> dict[str, Any]:
    if eb.get("abstained"):
        return _block(
            abstained=True,
            reason="No graded memory reviews yet.",
            coverage_pct=eb.get("coverage_pct", 0.0),
            evidence="No graded memory reviews.",
            missing="Begin memory review.",
            next_action="Start a short memory block.",
        )
    return _block(
        abstained=False,
        point=eb.get("point"),
        low=eb.get("low"),
        high=eb.get("high"),
        unit="percent_recall",
        coverage_pct=eb.get("coverage_pct", 0.0),
        confidence=_confidence_from_count(total_reviews, low=20, medium=100, high=300),
        evidence=f"{total_reviews} memory reviews; supporting evidence only.",
        missing="Memory supports readiness but does not prove it.",
        next_action="Keep memory as maintenance; prioritise performance.",
        count=total_reviews,
        count_unit="Reps",
    )


def _shape_overall_performance(
    eb: dict[str, Any], total_correct: int, total_attempts: int, total_sets: int
) -> dict[str, Any]:
    if eb.get("abstained"):
        return _block(
            abstained=True,
            reason="No performance attempts yet.",
            coverage_pct=eb.get("coverage_pct", 0.0),
            evidence="No exam-style attempts.",
            missing="Answer performance questions.",
            next_action="Do a performance set.",
        )
    return _block(
        abstained=False,
        point=eb.get("point"),
        low=eb.get("low"),
        high=eb.get("high"),
        unit="percent_correct",
        coverage_pct=eb.get("coverage_pct", 0.0),
        confidence=_confidence_from_count(total_attempts, low=10, medium=40, high=120),
        evidence=f"{total_correct}/{total_attempts} first-answer correct overall.",
        missing=None if total_attempts >= 40 else "More attempts would tighten this.",
        next_action="Keep performance sets varied across sections.",
        count=total_sets,
        count_unit="Sets",
    )


def _shape_overall_readiness(
    eb: dict[str, Any],
    engine_sections: dict[str, Any],
    total_attempts: int,
    total_reviews: int,
    agg: dict[str, dict[str, int]],
    coverage_pct: dict[str, float],
) -> dict[str, Any]:
    if eb.get("abstained"):
        all_ready = all(
            not engine_sections[s]["readiness"]["abstained"] for s in schema.SECTIONS
        )
        bits = []
        if not all_ready:
            bits.append("some sections lack coverage or performance sets")
        if total_reviews < OVERALL_MIN_GRADED_REVIEWS:
            bits.append(f"{total_reviews}/{OVERALL_MIN_GRADED_REVIEWS} reviews")
        if total_attempts < OVERALL_MIN_PERF_ATTEMPTS:
            bits.append(
                f"{total_attempts}/{OVERALL_MIN_PERF_ATTEMPTS} performance attempts"
            )
        return _block(
            abstained=True,
            reason="Not enough evidence for an honest overall readiness score.",
            coverage_pct=eb.get("coverage_pct", 0.0),
            evidence="Evidence is still thin; strict abstention beats fake precision.",
            missing="; ".join(bits) or None,
            next_action=_weakest_section_action(agg, coverage_pct),
        )
    full = (
        total_reviews >= OVERALL_MIN_GRADED_REVIEWS
        and total_attempts >= OVERALL_MIN_PERF_ATTEMPTS
    )
    if full:
        evidence = (
            f"All four sections estimated; {total_attempts} attempts, "
            f"{total_reviews} reviews."
        )
        confidence = "medium"
    else:
        evidence = "Low-confidence diagnostic estimate across all four sections."
        confidence = "low"
    return _block(
        abstained=False,
        point=eb.get("point"),
        low=eb.get("low"),
        high=eb.get("high"),
        unit="mcat_total",
        coverage_pct=eb.get("coverage_pct", 0.0),
        confidence=confidence,
        evidence=evidence,
        missing="A full-length will sharpen this estimate.",
        next_action=_weakest_section_action(agg, coverage_pct),
    )


def _weakest_section_action(
    agg: dict[str, dict[str, int]], coverage_pct: dict[str, float]
) -> str:
    weakest = None
    weakest_rank = 2.0
    for code, a in agg.items():
        score = (a["correct"] / a["attempts"]) if a["attempts"] else 0.0
        rank = score * 0.6 + coverage_pct.get(code, 0.0) * 0.4
        if rank < weakest_rank:
            weakest_rank = rank
            weakest = code
    if weakest is None:
        return "Do a balanced Mini-MCAT."
    return f"Focus next on {schema.SECTION_NAMES[weakest]} (weakest evidence)."


# Dev override
#############################################################################


def _pct_block(label_pct: float, unit: str) -> dict[str, Any]:
    p = max(0.0, min(100.0, float(label_pct)))
    return _block(
        abstained=False,
        point=round(p, 1),
        low=round(max(0.0, p - 6), 1),
        high=round(min(100.0, p + 6), 1),
        unit=unit,
        coverage_pct=1.0,
        confidence="medium",
        evidence="Dev override.",
        missing=None,
        next_action="Dev override active.",
    )


def _dev_override_scores(override: dict[str, Any]) -> dict[str, Any]:
    """Build a fully-populated scores payload from manual dev values."""
    mem_pct = float(override.get("memory_pct", 0) or 0)
    perf_pct = float(override.get("performance_pct", 0) or 0)
    secs = override.get("sections", {}) or {}

    total = 0
    sections: dict[str, Any] = {}
    for code in schema.SECTIONS:
        sc = int(round(float(secs.get(code, 125) or 125)))
        sc = max(SECTION_MIN, min(SECTION_MAX, sc))
        total += sc
        sections[code] = {
            "name": schema.SECTION_NAMES[code],
            "coverage_pct": 1.0,
            "covered_topics": 0,
            "total_topics": 0,
            "memory": _pct_block(mem_pct, "percent_recall"),
            "performance": _pct_block(perf_pct, "percent_correct"),
            "readiness": _block(
                abstained=False,
                point=sc,
                low=max(SECTION_MIN, sc - 1),
                high=min(SECTION_MAX, sc + 1),
                unit="section_score",
                coverage_pct=1.0,
                confidence="medium",
                evidence="Dev override.",
                missing=None,
                next_action="Dev override active.",
            ),
        }

    readiness = _block(
        abstained=False,
        point=total,
        low=max(TOTAL_MIN, total - 4),
        high=min(TOTAL_MAX, total + 4),
        unit="mcat_total",
        coverage_pct=1.0,
        confidence="medium",
        evidence="Dev override — readiness is the sum of section scores.",
        missing=None,
        next_action="Dev override active.",
    )
    return {
        "generated_at": int(time.time()),
        "ai_enabled": False,
        "memory": _pct_block(mem_pct, "percent_recall"),
        "performance": _pct_block(perf_pct, "percent_correct"),
        "readiness": readiness,
        "sections": sections,
    }


# Helpers
#############################################################################


def _block(
    *,
    abstained: bool,
    coverage_pct: float,
    evidence: str,
    next_action: str,
    missing: str | None = None,
    reason: str | None = None,
    point: float | int | None = None,
    low: float | int | None = None,
    high: float | int | None = None,
    unit: str | None = None,
    confidence: str | None = None,
    count: int | None = None,
    count_unit: str | None = None,
) -> dict[str, Any]:
    return {
        "abstained": abstained,
        "abstention_reason": reason,
        "point": point,
        "low": low,
        "high": high,
        "unit": unit,
        "confidence": confidence,
        "coverage_pct": round(coverage_pct, 3),
        "evidence": evidence,
        "missing": missing,
        "best_next_action": next_action,
        "count": count,
        "count_unit": count_unit,
        "updated_at": int(time.time()),
    }


def _confidence_from_count(count: int, *, low: int, medium: int, high: int) -> str:
    if count >= high:
        return "high"
    if count >= medium:
        return "medium"
    if count >= low:
        return "low-medium"
    return "low"


def _downgrade(confidence: str) -> str:
    order = ["low", "low-medium", "medium", "high"]
    if confidence not in order:
        return "low"
    idx = max(0, order.index(confidence) - 1)
    return order[idx]
