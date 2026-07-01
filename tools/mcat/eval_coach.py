# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Held-out evaluation for the AI study coach.

Runs the coach (the AI feature that reads a student's measured scores and
recommends the single best next action) over a GOLD SET of score profiles it
never sees in any prompt, and compares it to a simple rule-based baseline.

The baseline is the "simpler method" the AI must beat: it can only ever say
'memory' or 'performance' (memory when recall <= applied accuracy, else
performance). The coach earns its keep by ALSO recognizing when the real
bottleneck is COVERAGE, when a strong student should just stay BALANCED, and by
naming the weakest section for performance work.

Reports:
  - focus accuracy: did the coach pick the right TYPE of next action?
  - section-hit rate: on performance items, did it name the right section?
  - a side-by-side vs. the rule-based baseline
  - PASS/FAIL against the cutoff declared in the gold file

Re-runnable and grounded in the same coach code path both apps use (iOS mirrors
this prompt exactly). Reproduce with:

    OPENAI_API_KEY=sk-... PYTHONPATH="pylib:out/pylib" \\
        out/pyenv/bin/python tools/mcat/eval_coach.py

(The key is also read from pylib/anki/mcat/.openai_key if the env var is unset.)
"""

from __future__ import annotations

import argparse
import json
import tempfile
from pathlib import Path
from typing import Any

from anki.collection import Collection
from anki.mcat import ai

_GOLD = Path(__file__).with_name("eval_data") / "coach_gold.json"
_SECTIONS = ("bb", "cp", "ps", "cars")


def _block(value: Any) -> dict[str, Any]:
    """Expand a compact point (or None) into the ScoreBlock shape the coach reads."""
    return {"point": value, "abstained": value is None}


def _to_scores(facts: dict[str, Any]) -> dict[str, Any]:
    """Build the rich scores dict `ai.coach_recommendation` consumes from the
    compact gold `facts` (the same numbers the app grounds the coach in)."""
    sections = {}
    for code, s in facts["sections"].items():
        sections[code] = {
            "coverage_pct": s.get("coverage_pct", 0.0),
            "memory": _block(s.get("memory")),
            "performance": _block(s.get("performance")),
            "readiness": _block(s.get("readiness")),
        }
    return {
        "memory": _block(facts.get("memory")),
        "performance": _block(facts.get("performance")),
        "readiness": _block(facts.get("readiness")),
        "sections": sections,
    }


def baseline_focus(facts: dict[str, Any]) -> str:
    """The simpler method: a 2-way rule that can only say memory or performance."""
    mem = facts.get("memory") or 0
    perf = facts.get("performance") or 0
    return "memory" if mem <= perf else "performance"


def baseline_section(facts: dict[str, Any]) -> str:
    """Naive weakest section = lowest applied accuracy (None treated as high)."""
    sections = facts["sections"]

    def perf(code: str) -> float:
        v = sections.get(code, {}).get("performance")
        return v if v is not None else 101.0

    return min(_SECTIONS, key=perf)


def run() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gold", default=str(_GOLD))
    args = parser.parse_args()

    gold = json.loads(Path(args.gold).read_text(encoding="utf-8"))
    items = gold["items"]
    cutoff = gold["cutoff"]

    if not ai.available():
        print("NO API KEY configured — set OPENAI_API_KEY or add .openai_key.")
        return 2

    col = Collection(tempfile.mktemp(suffix=".anki2"))

    ai_focus_correct = 0
    base_focus_correct = 0
    ai_section_hit = 0
    base_section_hit = 0
    section_total = 0
    rows = []

    for it in items:
        facts = it["facts"]
        expected_focus = it["expected_focus"]
        expected_section = it.get("expected_section", [])

        rec = ai.coach_recommendation(col, scores=_to_scores(facts)) or {}
        focus = rec.get("focus", "error")
        section = rec.get("section", "")

        b_focus = baseline_focus(facts)
        b_section = baseline_section(facts)

        if focus in expected_focus:
            ai_focus_correct += 1
        if b_focus in expected_focus:
            base_focus_correct += 1
        if expected_section:
            section_total += 1
            if section in expected_section:
                ai_section_hit += 1
            if b_section in expected_section:
                base_section_hit += 1

        rows.append(
            (it["name"], expected_focus, focus, b_focus, expected_section, section)
        )

    col.close()

    n = len(items)
    ai_focus_acc = ai_focus_correct / n
    base_focus_acc = base_focus_correct / n
    ai_sec_rate = (ai_section_hit / section_total) if section_total else 1.0
    base_sec_rate = (base_section_hit / section_total) if section_total else 1.0

    print("=" * 66)
    print("AI Study Coach — held-out evaluation")
    print("=" * 66)
    print(f"Gold profiles: {n}  (section-specific: {section_total})")
    print(f"Model: {ai._MODEL}")
    print("-" * 66)
    print(f"{'metric':<28}{'AI coach':>14}{'rule baseline':>16}")
    print(f"{'focus accuracy':<28}{ai_focus_acc:>13.0%}{base_focus_acc:>16.0%}")
    print(f"{'section-hit (perf items)':<28}{ai_sec_rate:>13.0%}{base_sec_rate:>16.0%}")
    print("-" * 66)
    print("Per-item (expected focus | AI | baseline):")
    for name, exp_f, a_f, b_f, exp_s, a_s in rows:
        flag = " " if a_f in exp_f else "x"
        sec = f"  section: want {exp_s} got '{a_s}'" if exp_s else ""
        print(f"  [{flag}] {name}")
        print(f"        focus want {exp_f} | AI '{a_f}' | base '{b_f}'{sec}")
    print("-" * 66)

    min_acc = cutoff["min_focus_accuracy"]
    min_sec = cutoff["min_section_hit"]
    beats_baseline = ai_focus_acc > base_focus_acc
    passed = ai_focus_acc >= min_acc and ai_sec_rate >= min_sec and beats_baseline

    print(
        f"Cutoff: focus accuracy >= {min_acc:.0%} AND section-hit >= {min_sec:.0%} "
        f"AND beats baseline"
    )
    print(
        f"AI focus {ai_focus_acc:.0%} vs baseline {base_focus_acc:.0%}  "
        f"-> beats baseline: {beats_baseline}"
    )
    print(
        f"RESULT: {'PASS — coach is safe to ship' if passed else 'FAIL — do not ship AI coach'}"
    )
    print("=" * 66)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(run())
