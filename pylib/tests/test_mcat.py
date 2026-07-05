# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Integration tests for the MCAT Speedrun layer.

These exercise the Rust Mastery Query end to end from Python, and prove that the
surrounding MCAT data flow leaves undo and collection integrity intact.
"""

from __future__ import annotations

import datetime

from anki.mcat import ai, content, planner, schema, scoring, store
from tests.shared import getEmptyCol

# COVERAGE_STATUS_FULL from proto/anki/mastery.proto
COVERAGE_FULL = 3
COVERAGE_MEMORY_ONLY = 1


def test_mastery_query_end_to_end():
    col = getEmptyCol()
    counts = content.load_seed_deck(col)
    assert counts["memory"] > 0
    assert counts["performance"] > 0

    resp = col._backend.get_topic_mastery("")
    assert len(resp.topics) > 0
    by_id = {t.topic_id: t for t in resp.topics}

    # enzymes seed has both a memory and a performance item -> full coverage.
    enzymes = by_id["bb.enzymes"]
    assert enzymes.section == schema.SECTION_BB
    assert enzymes.memory_cards >= 1
    assert enzymes.performance_cards >= 1
    assert enzymes.coverage == COVERAGE_FULL

    # amino_acids has only a memory item in the seed -> memory-only coverage.
    amino = by_id["bb.amino_acids"]
    assert amino.coverage == COVERAGE_MEMORY_ONLY

    # Performance attempts stored in the config flow into the query.
    attempt = store.new_attempt(
        note_id=None,
        card_id=None,
        section=schema.SECTION_BB,
        topic_ids=["bb.enzymes"],
        difficulty=3,
        source_id="scaffold",
        mode=schema.MODE_PERFORMANCE,
        phase=schema.PHASE_DAILY,
        first_choice="A",
        first_correct=True,
        confidence=schema.CONFIDENCE_CERTAIN,
        first_time_ms=4200,
    )
    store.add_attempt(col, attempt)

    resp2 = col._backend.get_topic_mastery("")
    by_id2 = {t.topic_id: t for t in resp2.topics}
    enzymes = by_id2["bb.enzymes"]
    assert enzymes.performance_attempts >= 1
    assert enzymes.performance_first_correct >= 1
    assert enzymes.calibration_certain >= 1
    assert resp2.total_performance_attempts >= 1

    # Section filter restricts the result set.
    bb_resp = col._backend.get_topic_mastery(schema.SECTION_BB)
    assert all(t.section == schema.SECTION_BB for t in bb_resp.topics)

    col.close()


def test_mastery_query_section_coverage_counts():
    col = getEmptyCol()
    content.load_seed_deck(col)
    resp = col._backend.get_topic_mastery(schema.SECTION_CP)
    # Every CP topic returned should belong to CP.
    assert resp.topics
    assert all(t.topic_id.startswith("cp.") for t in resp.topics)
    col.close()


def _log_attempts(correct_by_section: dict[str, int]) -> list[dict]:
    """Two performance sets/section as engine attempt events (ids namespaced by
    section so a local + remote log union without collisions)."""
    out: list[dict] = []
    for section, correct in correct_by_section.items():
        for batch in ("a", "b"):
            for i in range(10):
                out.append(
                    {
                        "id": f"att-{section}-{batch}-{i}",
                        "section": section,
                        "question_key": f"{section}-q{batch}{i}",
                        "ts": 1000,
                        "first_correct": i < correct,
                        "batch_id": f"{section}-{batch}",
                    }
                )
    return out


def _log_reviews(correct_by_section: dict[str, int], total: int = 30) -> list[dict]:
    out: list[dict] = []
    for section, correct in correct_by_section.items():
        for i in range(total):
            out.append(
                {
                    "id": f"rev-{section}-{i}",
                    "card_key": f"{section}-c{i}",
                    "section": section,
                    "ts": 1000 + i,
                    "rating": 3 if i < correct else 1,
                }
            )
    return out


def test_scores_are_deterministic_and_combined():
    """Pins the exact scores the shared engine produces from a known log. The iOS
    app runs the same engine, so these are the parity reference values."""
    col = getEmptyCol()
    col.set_config(
        store.KEY_MCAT_LOG,
        {
            "attempts": _log_attempts({"bb": 7, "cp": 6, "ps": 5, "cars": 8}),
            "reviews": _log_reviews({"bb": 24, "cp": 20, "ps": 18, "cars": 26}),
        },
    )

    s = scoring.compute_scores(col)

    # Overall (displayed values are Math.round / Int(rounded), both half-up).
    assert round(s["memory"]["point"]) == 73
    assert round(s["performance"]["point"]) == 65
    assert s["readiness"]["point"] == 507
    assert s["readiness"]["low"] == 495
    assert s["readiness"]["high"] == 518
    assert not s["readiness"]["abstained"]

    # Per-section readiness (from performance proportions via the shared anchors).
    expected = {
        "bb": (128, 124, 130),
        "cp": (126, 123, 129),
        "ps": (124, 122, 128),
        "cars": (129, 126, 131),
    }
    for code, (pt, lo, hi) in expected.items():
        r = s["sections"][code]["readiness"]
        assert (r["point"], r["low"], r["high"]) == (pt, lo, hi)

    col.close()


def test_scores_combine_remote_device_logs():
    """The other device's synced LOG folds into the scores (replay-union)."""
    col = getEmptyCol()
    # Local log: only bb (14/20). Remote (other device) log: the other sections.
    col.set_config(
        store.KEY_MCAT_LOG, {"attempts": _log_attempts({"bb": 7}), "reviews": []}
    )
    col.set_config(
        store.KEY_REMOTE_MCAT_LOG,
        {"attempts": _log_attempts({"cp": 6, "ps": 5, "cars": 8}), "reviews": []},
    )
    s = scoring.compute_scores(col)
    # 14 + 12 + 10 + 16 = 52 correct of 80 = 65%.
    assert round(s["performance"]["point"]) == 65
    assert s["performance"]["count"] == 8  # 2 sets/section across 4 sections
    col.close()


def test_diagnostic_readiness_exception():
    """After a broad diagnostic (one set/section), the full gate isn't met but a
    low-confidence readiness estimate is still shown (mirrors iOS)."""
    col = getEmptyCol()
    attempts = []
    for section, correct in {"bb": 7, "cp": 6, "ps": 5, "cars": 8}.items():
        for i in range(10):
            attempts.append(
                {
                    "id": f"d-{section}-{i}",
                    "section": section,
                    "question_key": f"{section}-q{i}",
                    "ts": 1000,
                    "first_correct": i < correct,
                    "batch_id": f"{section}-diag",
                }
            )
    col.set_config(store.KEY_MCAT_LOG, {"attempts": attempts, "reviews": []})
    store.update_profile(col, diagnostic_kind="standard")

    s = scoring.compute_scores(col)
    assert not s["readiness"]["abstained"]
    assert s["readiness"]["confidence"] == "low"
    assert 472 <= s["readiness"]["low"] <= s["readiness"]["high"] <= 528
    col.close()


def test_undo_and_integrity_preserved():
    col = getEmptyCol()
    content.load_seed_deck(col)

    # The Mastery Query is read-only, so it must not break integrity or undo.
    col._backend.get_topic_mastery("")

    notetypes = schema.ensure_mcat_notetypes(col)
    nt = col.models.get(notetypes[schema.NOTETYPE_MEMORY])
    note = col.new_note(nt)
    note["Front"] = "undo probe"
    note["Back"] = "value"
    note.tags = schema.build_tags(
        section=schema.SECTION_PS,
        topic_ids=["ps.cognition"],
        card_type=schema.CARD_TYPE_MEMORY,
        difficulty=2,
        source_id="scaffold",
        mode=schema.MODE_MEMORY,
    )
    before = col.note_count()
    col.add_note(note, col.decks.id(schema.MCAT_DECK_NAME))
    assert col.note_count() == before + 1

    # Undo should be available and revert the add.
    assert col.undo_status().undo != ""
    col.undo()
    assert col.note_count() == before

    # Mastery query still works after undo.
    col._backend.get_topic_mastery("")

    # Collection integrity is intact.
    _, ok = col.fix_integrity()
    assert ok

    col.close()


# Store: content keys, second-pass labels, dev login, event log, profile
#############################################################################


def test_mcat_card_key_is_stable_and_distinct():
    """The content key is a deterministic 16-hex slug that the engine and iOS
    both recompute, so the same card must always hash the same everywhere."""
    a = store.mcat_card_key("m", "bb", "What is glycolysis?")
    assert a == store.mcat_card_key("m", "bb", "What is glycolysis?")
    assert len(a) == 16 and all(c in "0123456789abcdef" for c in a)
    # Any component change -> a different key.
    assert a != store.mcat_card_key("p", "bb", "What is glycolysis?")  # kind
    assert a != store.mcat_card_key("m", "cp", "What is glycolysis?")  # section
    assert a != store.mcat_card_key("m", "bb", "What is the citric cycle?")  # text


def test_second_pass_label_covers_every_branch():
    def label(first_correct, second_choice, second_correct, confidence, first="A"):
        attempt = {
            "first_choice": first,
            "first_correct": first_correct,
            "confidence": confidence,
        }
        store.apply_second_pass(
            attempt,
            second_choice=second_choice,
            second_correct=second_correct,
            reasoning_text="because",
        )
        return attempt["second_pass_label"], attempt["changed_answer"]

    # Recovered a missed question on the second look.
    assert label(False, "B", True, "guessing") == ("correct_after_retry", True)
    # Still wrong after the retry.
    assert label(False, "C", False, "guessing") == ("incorrect_after_retry", True)
    # Right both times but switched answers.
    assert label(True, "B", True, "certain") == ("changed_answer", True)
    # Held a correct, confident answer.
    assert label(True, "A", True, "certain") == ("stayed_confident", False)
    # Held a correct answer but wasn't sure.
    assert label(True, "A", True, "guessing") == ("stayed_uncertain", False)


def test_is_dev_login():
    assert store.is_dev_login("dev@mcat.com", "devaccount")
    assert store.is_dev_login("DEV@MCAT.COM", "devaccount")  # email case-insensitive
    assert not store.is_dev_login("dev@mcat.com", "wrong")
    assert not store.is_dev_login("dev@mcat.com", "DEVACCOUNT")  # password is exact
    assert not store.is_dev_login("someone@else.com", "devaccount")


def test_profile_defaults_and_backfill():
    col = getEmptyCol()
    p = store.get_profile(col)
    assert p["ai_enabled"] is True
    assert p["daily_minutes"] == 120
    assert p["onboarding_done"] is False
    assert p["last_diagnostic_date"] is None

    # A profile persisted by an older build (missing new keys) gets them backfilled.
    col.set_config(store.KEY_PROFILE, {"name": "Sam", "daily_minutes": 45})
    p2 = store.get_profile(col)
    assert p2["name"] == "Sam" and p2["daily_minutes"] == 45
    assert p2["ai_enabled"] is True  # backfilled default
    assert "last_diagnostic_date" in p2
    col.close()


def test_engine_event_log_append_and_tally():
    col = getEmptyCol()
    assert store.get_mcat_log(col) == {"reviews": [], "attempts": []}

    store.append_review_event(col, card_key="bb-c1", section="bb", rating=3)
    store.append_review_event(col, card_key="", section="bb", rating=3)  # no-op
    store.append_attempt_events(
        col,
        [
            {
                "section": "bb",
                "question_key": "q1",
                "first_correct": True,
                "batch_id": "bb-a",
            },
            {
                "section": "bb",
                "question_key": "q2",
                "first_correct": False,
                "batch_id": "bb-a",
            },
        ],
    )
    log = store.get_mcat_log(col)
    assert len(log["reviews"]) == 1  # empty-key event was skipped
    assert len(log["attempts"]) == 2
    # Every event is assigned a stable id + timestamp for merge/replay.
    assert all(e["id"] and e["ts"] for e in log["reviews"] + log["attempts"])

    store.record_memory_review(col, "bb", good=True)
    store.record_memory_review(col, "bb", good=False)
    tally = store.get_memory_reviews(col)["bb"]
    assert tally == {"reviews": 2, "reviewsCorrect": 1}
    col.close()


# Planner: roadmap scaling, exam phases, deterministic keys, streak
#############################################################################


def _iso_in(days: int) -> str:
    return (datetime.date.today() + datetime.timedelta(days=days)).isoformat()


def test_roadmap_scales_with_daily_minutes():
    col = getEmptyCol()
    store.update_profile(col, daily_minutes=30)
    small = planner.build_daily_plan(col)
    store.update_profile(col, daily_minutes=120)
    large = planner.build_daily_plan(col)
    # More available time -> more planned minutes and more blocks.
    assert large["planned_minutes"] > small["planned_minutes"]
    assert len(large["blocks"]) > len(small["blocks"])
    # No single block exceeds the cap.
    assert all(b["minutes"] <= planner.MAX_BLOCK_MINUTES for b in large["blocks"])
    col.close()


def test_roadmap_keys_are_deterministic_for_sync():
    """Block ids are random uuids, but the stable `key` slugs must be identical
    on rebuild (and on iOS) — that's what lets completion sync across devices."""
    col = getEmptyCol()
    store.update_profile(col, daily_minutes=90, exam_date=_iso_in(120))
    keys1 = [b["key"] for b in planner.build_daily_plan(col)["blocks"]]
    keys2 = [b["key"] for b in planner.build_daily_plan(col)["blocks"]]
    assert keys1 == keys2
    assert len(keys1) == len(set(keys1))  # unique within a day
    col.close()


def test_roadmap_final_phase_disables_flashcards():
    col = getEmptyCol()
    # Far exam -> foundation phase includes memory (flashcard) blocks.
    store.update_profile(col, exam_date=_iso_in(120))
    foundation = planner.build_daily_plan(col)
    assert foundation["phase"] == "foundation"
    assert any(b["kind"] == "memory" for b in foundation["blocks"])

    # Within two weeks -> final phase drops flashcards entirely (PRD rule).
    store.update_profile(col, exam_date=_iso_in(7))
    final = planner.build_daily_plan(col)
    assert final["phase"] == "final"
    assert all(b["kind"] != "memory" for b in final["blocks"])
    col.close()


def test_full_length_guidance_and_diagnostic_spec():
    assert planner.full_length_guidance(None)["phase"] == "unscheduled"
    assert planner.full_length_guidance(7)["phase"] == "final"
    assert planner.full_length_guidance(30)["phase"] == "middle"
    assert planner.full_length_guidance(120)["phase"] == "early"

    assert planner.diagnostic_spec("quick")["per_section"] == 3
    assert planner.diagnostic_spec("best_estimate")["total"] == 40
    # Unknown kinds fall back to the standard diagnostic.
    assert planner.diagnostic_spec("bogus") == planner.diagnostic_spec("standard")


def test_required_complete_gate():
    assert planner.required_complete(
        {"blocks": [{"required": True, "completed": True}]}
    )
    assert not planner.required_complete(
        {
            "blocks": [
                {"required": True, "completed": True},
                {"required": True, "completed": False},
            ]
        }
    )
    # No required blocks -> not complete (nothing to earn the streak).
    assert not planner.required_complete(
        {"blocks": [{"required": False, "completed": True}]}
    )


def test_completing_the_roadmap_awards_a_streak():
    col = getEmptyCol()
    store.update_profile(col, daily_minutes=30)
    plan = planner.build_daily_plan(col)
    assert store.get_streak(col)["count"] == 0
    for block in plan["blocks"]:
        planner.complete_block(col, block["id"])
    streak = store.get_streak(col)
    assert streak["count"] == 1
    assert streak["last_completed_date"] == datetime.date.today().isoformat()
    col.close()


# Scoring: pure helpers, aggregation, coverage, weakest section, dev override
#############################################################################


def test_confidence_from_count_thresholds():
    conf = scoring._confidence_from_count
    assert conf(120, low=10, medium=40, high=120) == "high"
    assert conf(40, low=10, medium=40, high=120) == "medium"
    assert conf(10, low=10, medium=40, high=120) == "low-medium"
    assert conf(0, low=10, medium=40, high=120) == "low"


def test_downgrade_confidence():
    assert scoring._downgrade("high") == "medium"
    assert scoring._downgrade("medium") == "low-medium"
    assert scoring._downgrade("low") == "low"
    assert scoring._downgrade("nonsense") == "low"


def test_aggregate_from_log():
    log = {
        "attempts": [
            {"section": "bb", "first_correct": True, "batch_id": "bb-a"},
            {"section": "bb", "first_correct": False, "batch_id": "bb-a"},
            {"section": "bb", "first_correct": True, "batch_id": "bb-b"},
            {"section": "zz", "first_correct": True, "batch_id": "x"},  # ignored
        ],
        "reviews": [
            {"section": "bb", "rating": 3},
            {"section": "bb", "rating": 1},
        ],
    }
    agg = scoring._aggregate_from_log(log)
    assert agg["bb"]["attempts"] == 3
    assert agg["bb"]["correct"] == 2
    assert agg["bb"]["sets"] == 2  # two distinct batch_ids
    assert agg["bb"]["reviews"] == 2
    assert agg["bb"]["reviewsCorrect"] == 1
    assert agg["cp"]["attempts"] == 0  # untouched section stays zeroed


class _FakeTaxonomy:
    def __init__(self, topics: dict[str, list[str]]):
        self._topics = topics

    def topic_ids(self, section: str) -> list[str]:
        return self._topics.get(section, [])


def test_coverage_is_performance_based():
    tax = _FakeTaxonomy({"bb": ["t1", "t2", "t3"]})
    perf = {"bb": {"t1", "t2"}}
    covered, total, pct = scoring._coverage("bb", perf, tax)
    assert (covered, total) == (2, 3)
    assert abs(pct - 2 / 3) < 1e-9
    # A performance topic outside the taxonomy still expands the universe.
    perf2 = {"bb": {"t1", "t2", "t3", "t4"}}
    covered2, total2, pct2 = scoring._coverage("bb", perf2, tax)
    assert (covered2, total2, pct2) == (4, 4, 1.0)


def test_weakest_section_action_points_at_the_worst():
    agg = {
        "bb": {"correct": 9, "attempts": 10},
        "cp": {"correct": 1, "attempts": 10},  # clearly weakest
        "ps": {"correct": 8, "attempts": 10},
        "cars": {"correct": 7, "attempts": 10},
    }
    cov = {"bb": 0.8, "cp": 0.8, "ps": 0.8, "cars": 0.8}
    action = scoring._weakest_section_action(agg, cov)
    assert schema.SECTION_NAMES["cp"] in action


def test_dev_override_scores_sum_and_clamp():
    override = {
        "memory_pct": 82,
        "performance_pct": 71,
        # ps is out of range and must clamp into [118, 132].
        "sections": {"bb": 130, "cp": 120, "ps": 200, "cars": 128},
    }
    s = scoring._dev_override_scores(override)
    assert s["memory"]["point"] == 82.0
    assert s["performance"]["point"] == 71.0
    assert s["sections"]["ps"]["readiness"]["point"] == 132  # clamped
    # Total readiness is the sum of the (clamped) section scores.
    assert s["readiness"]["point"] == 130 + 120 + 132 + 128
    assert s["readiness"]["low"] >= scoring.TOTAL_MIN
    assert s["readiness"]["high"] <= scoring.TOTAL_MAX


# AI layer: SVG safety, title parsing, cache, and the on/off gate
#############################################################################


def test_sanitize_svg_keeps_safe_vector_art():
    safe = (
        '<svg viewBox="0 0 420 240" xmlns="http://www.w3.org/2000/svg">'
        '<circle cx="10" cy="10" r="5" fill="#6366f1"/>'
        '<text x="10" y="30" fill="currentColor">HA</text></svg>'
    )
    # Surrounding prose is stripped; the xmlns http(s) namespace is allowed.
    assert ai.sanitize_svg("TITLE: Buffer\n" + safe + "\ntrailing") == safe


def test_sanitize_svg_rejects_active_or_external_content():
    bad = [
        "<svg><script>alert(1)</script></svg>",
        '<svg onload="x()"></svg>',
        '<svg><a href="http://evil">x</a></svg>',
        '<svg><image href="http://evil.png"/></svg>',
        "<svg><foreignObject><b>hi</b></foreignObject></svg>",
        "not an svg at all",
        "<svg>" + "p" * 9001 + "</svg>",  # too large
    ]
    for text in bad:
        assert ai.sanitize_svg(text) is None, text
    assert ai.sanitize_svg(None) is None


def test_parse_title():
    assert ai._parse_title("TITLE: Buffer region\n<svg></svg>") == "Buffer region"
    assert ai._parse_title('TITLE: "Quoted"\n<svg></svg>') == "Quoted"
    assert ai._parse_title("no title here") is None
    assert ai._parse_title("TITLE: " + "z" * 100) == "z" * 48  # capped


def test_ai_cache_roundtrip():
    col = getEmptyCol()
    assert ai._cache_get(col, "missing") is None
    ai._cache_put(col, "k", "cached-value")
    assert ai._cache_get(col, "k") == "cached-value"
    col.close()


def test_ai_disabled_when_toggle_off():
    col = getEmptyCol()
    # With the toggle off, AI is gated off regardless of whether a key exists.
    store.update_profile(col, ai_enabled=False)
    assert ai.enabled(col) is False
    col.close()
