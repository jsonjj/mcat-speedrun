# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Leakage check for MCAT Speedrun content.

A simple, transparent guard against trivial leakage before any AI/eval work:

1. No performance question text is an exact duplicate of another (which would
   let a paraphrase/held-out split leak across train and test).
2. No performance explanation is identical to a memory card's answer (which
   would mean the "application" item is really just the memorised fact).

This is intentionally conservative and non-AI; it returns a non-zero exit code
if it finds problems, so it can run in CI against a content pack.

Usage:
    PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/leakage_check.py path/to/pack.json
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter


def normalise(text: str) -> str:
    return " ".join(text.lower().split())


def check_pack(data: dict) -> list[str]:
    problems: list[str] = []
    questions: list[str] = []
    memory_answers: set[str] = set()
    perf_explanations: list[tuple[str, str]] = []

    for item in data.get("items", []):
        kind = item.get("kind")
        if kind == "memory":
            memory_answers.add(normalise(str(item.get("back", ""))))
        elif kind == "performance":
            q = normalise(str(item.get("question", "")))
            if q:
                questions.append(q)
            perf_explanations.append(
                (
                    str(item.get("question", "")),
                    normalise(str(item.get("explanation", ""))),
                )
            )

    # 1) duplicate performance questions
    for q, count in Counter(questions).items():
        if count > 1:
            problems.append(
                f"Duplicate performance question appears {count}x: {q[:80]}"
            )

    # 2) explanation identical to a memory answer
    for question, explanation in perf_explanations:
        if explanation and explanation in memory_answers:
            problems.append(
                f"Performance explanation equals a memory answer (possible leakage): {question[:80]}"
            )

    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description="MCAT content leakage check")
    parser.add_argument(
        "pack",
        nargs="?",
        default="pylib/anki/mcat/data/seed_deck.json",
        help="content-pack JSON to check",
    )
    args = parser.parse_args()

    with open(args.pack, encoding="utf-8") as f:
        data = json.load(f)

    problems = check_pack(data)
    if problems:
        print(f"Leakage check FAILED ({len(problems)} problem(s)):")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print("Leakage check passed: no trivial leakage detected.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
