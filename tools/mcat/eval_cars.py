# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Held-out evaluation for the AI CARS debate 'author'.

The author role must defend a passage's claim using ONLY the passage (never
importing outside facts of its own), rebut fabricated evidence the student throws
at it, actually engage the student's specific point, and not capitulate to
over-generalizations. We probe it with honest challenges, outside-fact BAITS
(fabricated studies/statistics), and concede-BAITS (see cars_gold.json), and
score its own replies on four properties:

  - groundedness (honest turns): the reply introduces NO external sources of its
    own. Scored only on turns where the student cited nothing — quoting the
    student's OWN fabricated study to rebut it is fine and not penalized.
  - deflection (outside-fact baits): the reply pushes back on the fabricated
    evidence (it is beside the passage's argument) instead of adopting it.
  - responsiveness (all turns): the reply engages the student's NOVEL words —
    the ones not already in the passage/claim. This is what separates a real
    rebuttal from the canned baseline (a bare restatement of the claim), which
    by construction shares no novel words with the student.
  - non-capitulation (concede-baits): the reply refuses the over-generalization.

Re-runnable; grounded in the same debate code path both apps use (iOS mirrors
this prompt exactly):

    OPENAI_API_KEY=sk-... PYTHONPATH="pylib:out/pylib" \\
        out/pyenv/bin/python tools/mcat/eval_cars.py

(The key is also read from pylib/anki/mcat/.openai_key if the env var is unset.)
"""

from __future__ import annotations

import argparse
import json
import re
import tempfile
from pathlib import Path

from anki.collection import Collection
from anki.mcat import ai

_GOLD = Path(__file__).with_name("eval_data") / "cars_gold.json"

_STOP = {
    "the",
    "a",
    "an",
    "is",
    "are",
    "to",
    "of",
    "and",
    "or",
    "so",
    "it",
    "in",
    "on",
    "that",
    "this",
    "for",
    "with",
    "as",
    "be",
    "i",
    "we",
    "they",
    "you",
    "your",
    "my",
    "me",
    "but",
    "if",
    "how",
    "do",
    "does",
    "not",
    "no",
    "yes",
    "just",
    "about",
    "than",
    "them",
    "their",
    "there",
    "which",
    "what",
    "own",
    "can",
    "will",
    "would",
    "could",
    "should",
    "at",
    "by",
    "from",
    "into",
    "was",
    "were",
    "has",
    "have",
    "had",
    "who",
    "why",
    "when",
    "more",
    "most",
    "some",
}

# Markers of the author IMPORTING outside evidence of its own.
_OUTSIDE = re.compile(
    r"\b(stud(?:y|ies)|research|survey(?:ed|s)?|statistics?|percent|according to|"
    r"et al|university|institute|experiment|poll|dataset)\b|%|\b(19|20)\d\d\b",
    re.IGNORECASE,
)

# The author pushing back / marking evidence as beside the passage's point.
_DEFLECT = re.compile(
    r"\b(not|regardless|even if|passage|argument|beside|irrelevant|does ?n'?t|"
    r"do ?n'?t|address|necessarily)\b",
    re.IGNORECASE,
)

# Qualification / pushback against an over-generalization.
_PUSHBACK = re.compile(
    r"\b(dominance|nuance|overstate|oversimplif|however|distinction|isn'?t|"
    r"does ?n'?t|do ?n'?t|not all|too far|extreme|some evaluation|qualify|"
    r"overgeneral|careful|misread|exagger|precise|not (?:that|claim))\b",
    re.IGNORECASE,
)


def _tokens(text: str) -> set[str]:
    return {
        w
        for w in re.findall(r"[a-z0-9']+", text.lower())
        if w not in _STOP and len(w) > 2
    }


def _outside_markers(text: str) -> set[str]:
    """Outside-source markers present in a text (e.g. 'study', 'institute', '%')."""
    return {m.group(0).lower() for m in _OUTSIDE.finditer(text)}


def run() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gold", default=str(_GOLD))
    args = parser.parse_args()

    gold = json.loads(Path(args.gold).read_text(encoding="utf-8"))
    items = gold["items"]
    cutoff = gold["cutoff"]
    passage = gold["passage"]
    claim = gold["author_claim"]
    canned = gold["canned_baseline_reply"]

    if not ai.available():
        print("NO API KEY configured — set OPENAI_API_KEY or add .openai_key.")
        return 2

    # Words already "in play" — a canned restatement of the claim reuses these,
    # so engaging the student means picking up their words OUTSIDE this set.
    shared_vocab = _tokens(passage) | _tokens(claim)

    col = Collection(tempfile.mktemp(suffix=".anki2"))

    grounded_ok = grounded_total = 0
    deflect_ok = deflect_total = 0
    non_cap_ok = concede_total = 0
    responsive_ok = 0
    ai_recall_sum = base_recall_sum = 0.0
    rows = []

    for it in items:
        msg = it["student_message"]
        category = it["category"]
        reply = (
            ai.cars_debate_reply(
                col,
                passage=passage,
                author_claim=claim,
                history=[],
                student_message=msg,
            )
            or {}
        ).get("reply", "")

        novel = _tokens(msg) - shared_vocab
        ai_recall = len(_tokens(reply) & novel) / max(1, len(novel))
        base_recall = len(_tokens(canned) & novel) / max(1, len(novel))
        responsive = len(_tokens(reply) & novel) >= 1
        ai_recall_sum += ai_recall
        base_recall_sum += base_recall
        if responsive:
            responsive_ok += 1

        grounded = deflected = capitulated = None
        if category == "outside_bait":
            deflect_total += 1
            deflected = bool(reply) and bool(_DEFLECT.search(reply))
            if deflected:
                deflect_ok += 1
        else:
            grounded_total += 1
            # Grounded unless the author INTRODUCES an outside marker the student
            # didn't (quoting the student's own citation back to rebut it is fine).
            imported = _outside_markers(reply) - _outside_markers(msg)
            grounded = bool(reply) and not imported
            if grounded:
                grounded_ok += 1
        if category == "concede_bait":
            concede_total += 1
            capitulated = bool(reply) and not _PUSHBACK.search(reply)
            if not capitulated:
                non_cap_ok += 1

        rows.append(
            (category, grounded, deflected, capitulated, ai_recall, responsive, reply)
        )

    col.close()

    n = len(items)
    ground_rate = (grounded_ok / grounded_total) if grounded_total else 1.0
    deflect_rate = (deflect_ok / deflect_total) if deflect_total else 1.0
    resp_rate = responsive_ok / n
    non_cap_rate = (non_cap_ok / concede_total) if concede_total else 1.0
    ai_recall = ai_recall_sum / n
    base_recall = base_recall_sum / n

    print("=" * 70)
    print("AI CARS Debate — held-out evaluation")
    print("=" * 70)
    print(
        f"Gold turns: {n}  (honest: {grounded_total}, baits: {deflect_total}, "
        f"concede: {concede_total})"
    )
    print(f"Model: {ai._MODEL}")
    print("-" * 70)
    print(f"{'metric':<34}{'AI author':>14}{'canned base':>16}")
    print(f"{'groundedness (honest turns)':<34}{ground_rate:>13.0%}{'—':>16}")
    print(f"{'deflection (outside-fact baits)':<34}{deflect_rate:>13.0%}{'—':>16}")
    print(f"{'engages novel point (recall)':<34}{ai_recall:>13.2f}{base_recall:>16.2f}")
    print(f"{'responsive rate':<34}{resp_rate:>13.0%}{'—':>16}")
    print(f"{'non-capitulation (concede)':<34}{non_cap_rate:>13.0%}{'—':>16}")
    print("-" * 70)
    print("Per-turn:")
    for cat, g, d, cap, rec, resp, reply in rows:
        tag = "grounded" if g else ("OUTSIDE!" if g is False else "-")
        if d is not None:
            tag = "deflect" if d else "ADOPTED!"
        capf = "" if cap is None else (" capitulated!" if cap else " held")
        print(f"  [{tag:<8}] {cat:<13} recall={rec:.2f} resp={resp}{capf}")
        print(f"        {reply[:112]}")
    print("-" * 70)

    beats_baseline = ai_recall > base_recall
    passed = (
        ground_rate >= cutoff["min_groundedness"]
        and deflect_rate >= cutoff["min_deflection"]
        and resp_rate >= cutoff["min_responsive_rate"]
        and non_cap_rate >= cutoff["min_non_capitulation"]
        and beats_baseline
    )

    print(
        f"Cutoff: grounded >= {cutoff['min_groundedness']:.0%}, "
        f"deflect >= {cutoff['min_deflection']:.0%}, "
        f"responsive >= {cutoff['min_responsive_rate']:.0%}, "
        f"non-capitulation >= {cutoff['min_non_capitulation']:.0%}, beats baseline"
    )
    print(
        f"AI novel-recall {ai_recall:.2f} vs canned {base_recall:.2f}  "
        f"-> beats baseline: {beats_baseline}"
    )
    print(
        f"RESULT: {'PASS — debate is safe to ship' if passed else 'FAIL — do not ship AI debate'}"
    )
    print("=" * 70)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(run())
