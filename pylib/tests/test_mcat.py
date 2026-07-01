# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Integration tests for the MCAT Speedrun layer.

These exercise the Rust Mastery Query end to end from Python, and prove that the
surrounding MCAT data flow leaves undo and collection integrity intact.
"""

from __future__ import annotations

from anki.mcat import content, schema, scoring, store
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
    expected = {"bb": (128, 124, 130), "cp": (126, 123, 129),
                "ps": (124, 122, 128), "cars": (129, 126, 131)}
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
