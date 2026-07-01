# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Held-out evaluation for the AI reasoning grader.

Runs the grader (the AI feature that judges a student's free-response argument
against the question's official explanation) over a GOLD SET it never sees in any
prompt, and compares it to a simpler keyword-overlap baseline. Reports:

  - exact-label accuracy (sound / partially_sound / flawed)
  - flawed-missed rate: how often genuinely flawed reasoning was NOT called flawed
    (the costly error — never praise a wrong argument)
  - a side-by-side vs. the keyword baseline
  - PASS/FAIL against the cutoff declared in the gold file

This is re-runnable and deterministic given the same gold file + model. Anyone
can reproduce it:

    OPENAI_API_KEY=sk-... PYTHONPATH="pylib:out/pylib" \\
        out/pyenv/bin/python tools/mcat/eval_reasoning.py

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

_GOLD = Path(__file__).with_name("eval_data") / "reasoning_gold.json"
_LABELS = ("sound", "partially_sound", "flawed")
_STOP = {
    "the", "a", "an", "is", "are", "to", "of", "and", "or", "so", "it", "in",
    "on", "that", "this", "for", "with", "as", "be", "i", "we", "they", "which",
}


def _tokens(text: str) -> set[str]:
    return {w for w in re.findall(r"[a-z0-9]+", text.lower()) if w not in _STOP}


def keyword_baseline(explanation: str, student_reasoning: str) -> str:
    """A simple, transparent baseline: label by how much of the explanation's
    vocabulary the student's reasoning overlaps (Jaccard). No LLM."""
    exp, stu = _tokens(explanation), _tokens(student_reasoning)
    if not exp or not stu:
        return "flawed"
    overlap = len(exp & stu) / len(exp | stu)
    if overlap >= 0.28:
        return "sound"
    if overlap >= 0.12:
        return "partially_sound"
    return "flawed"


def _safe(label: str) -> str:
    """Collapse to the safety-critical distinction: flawed vs. not-flawed."""
    return "flawed" if label == "flawed" else "ok"


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

    ai_correct = 0
    base_correct = 0
    ai_flawed_missed = 0
    base_flawed_missed = 0
    flawed_total = 0
    rows = []

    for it in items:
        expected = it["expected"]
        result = ai.grade_reasoning(
            col,
            question=it["question"],
            choices=it["choices"],
            student_choice=it["student_choice"],
            correct_choice=it["correct_choice"],
            explanation=it["explanation"],
            student_reasoning=it["student_reasoning"],
        )
        ai_label = (result or {}).get("verdict", "error")
        base_label = keyword_baseline(it["explanation"], it["student_reasoning"])

        if ai_label == expected:
            ai_correct += 1
        if base_label == expected:
            base_correct += 1
        if expected == "flawed":
            flawed_total += 1
            if _safe(ai_label) != "flawed":
                ai_flawed_missed += 1
            if _safe(base_label) != "flawed":
                base_flawed_missed += 1
        rows.append((expected, ai_label, base_label))

    col.close()

    n = len(items)
    ai_acc = ai_correct / n
    base_acc = base_correct / n
    ai_miss = (ai_flawed_missed / flawed_total) if flawed_total else 0.0
    base_miss = (base_flawed_missed / flawed_total) if flawed_total else 0.0

    print("=" * 60)
    print("AI Reasoning Grader — held-out evaluation")
    print("=" * 60)
    print(f"Gold items: {n}  (flawed: {flawed_total})")
    print(f"Model: {ai._MODEL}")
    print("-" * 60)
    print(f"{'metric':<28}{'AI grader':>14}{'keyword base':>16}")
    print(f"{'exact-label accuracy':<28}{ai_acc:>13.0%}{base_acc:>16.0%}")
    print(f"{'flawed-missed rate':<28}{ai_miss:>13.0%}{base_miss:>16.0%}")
    print("-" * 60)
    print("Per-item (expected | AI | baseline):")
    for exp, a, b in rows:
        flag = " " if a == exp else "x"
        print(f"  [{flag}] {exp:<16} | {a:<16} | {b}")
    print("-" * 60)

    min_acc = cutoff["min_accuracy"]
    max_miss = cutoff["max_flawed_missed_rate"]
    beats_baseline = ai_acc > base_acc
    passed = ai_acc >= min_acc and ai_miss <= max_miss and beats_baseline

    print(f"Cutoff: accuracy >= {min_acc:.0%} AND flawed-missed <= {max_miss:.0%} "
          f"AND beats baseline")
    print(f"AI accuracy {ai_acc:.0%} vs baseline {base_acc:.0%}  "
          f"-> beats baseline: {beats_baseline}")
    print(f"RESULT: {'PASS — grader is safe to ship' if passed else 'FAIL — do not ship AI grading'}")
    print("=" * 60)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(run())
