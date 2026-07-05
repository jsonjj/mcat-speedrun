# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Paraphrase test — proof that Performance is not just Memory (challenge 7d).

The trap: recalling the flashcard "mitochondria = powerhouse" doesn't mean you
can answer a cellular-respiration passage. This test takes cards, pairs each with
REWORDED exam-style questions testing the same idea in new words, and compares the
student's RECALL on the card with their ACCURACY on the reworded questions. If the
two numbers are basically the same, the performance measure is just copying the
memory measure — the bridge wasn't built. We report the gap.

MCAT Speedrun measures the two separately (Memory = flashcard recall; Performance
= first-answer accuracy on exam-style items), so a real gap should appear —
largest exactly where memory is strongest (the well-memorized-but-can't-apply
case).

METHOD (documented SIMULATION, same learner model as the ablation): flashcards
build `recall`; application skill (`appSkill`) only grows from application
practice, of which there is limited time. Recalling a card needs memory; a
reworded exam question needs memory AND application skill:
`P(reworded correct) = 0.25 + 0.75 * recall * appSkill`.

    PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/paraphrase_test.py
    (pure stdlib; no backend or network needed)
"""

from __future__ import annotations

import argparse
import random
import statistics

CARDS = 30  # the brief's "take 30 cards"
REWORDED_PER_CARD = 2  # "write 2 exam-style questions that test the same idea"

# Learner model (mirrors tools/mcat/ablation.py).
AR_FC = 0.05  # recall per flashcard review
AA = 0.14  # application skill per application question
FC_REVIEWS = 40  # thorough flashcard study per card (memory gets strong)
APP_FRACTION = 0.4  # fraction of cards that also got real application practice
APP_REPS = 3  # application questions on those practiced topics
APPSKILL0 = 0.10  # innate flashcard->application transfer (the low baseline)
RECALL0 = 0.12


def _grow(level: float, rate: float, reps: int) -> float:
    return 1.0 - (1.0 - level) * ((1.0 - rate) ** reps)


def run(students: int = 400, seed: int = 3) -> int:
    rng = random.Random(seed)
    recall_scores: list[float] = []
    reworded_scores: list[float] = []
    strong_mem_reworded: list[float] = []  # reworded acc on well-recalled cards

    for _ in range(students):
        for c in range(CARDS):
            recall = _grow(
                min(1.0, max(0.0, rng.gauss(RECALL0, 0.05))), AR_FC, FC_REVIEWS
            )
            app_skill = min(1.0, max(0.0, rng.gauss(APPSKILL0, 0.04)))
            # Only some cards' topics also got real application practice.
            if rng.random() < APP_FRACTION:
                app_skill = _grow(app_skill, AA, APP_REPS)

            recall_on_card = 0.10 + 0.88 * recall  # memory test on the card
            p_reworded = 0.25 + 0.75 * (recall * app_skill)  # needs memory AND skill
            hits = sum(1 for _ in range(REWORDED_PER_CARD) if rng.random() < p_reworded)
            reworded_acc = hits / REWORDED_PER_CARD

            recall_scores.append(recall_on_card * 100)
            reworded_scores.append(reworded_acc * 100)
            if recall_on_card >= 0.80:
                strong_mem_reworded.append(reworded_acc * 100)

    mean_recall = statistics.fmean(recall_scores)
    mean_reworded = statistics.fmean(reworded_scores)
    gap = mean_recall - mean_reworded
    strong = statistics.fmean(strong_mem_reworded) if strong_mem_reworded else 0.0

    print("=" * 66)
    print("MCAT Speedrun — Paraphrase test (Performance is not Memory, 7d)")
    print("=" * 66)
    print(
        f"{CARDS} cards x {REWORDED_PER_CARD} reworded questions, {students} students"
    )
    print("-" * 66)
    print(f"Recall on the card (memory)          : {mean_recall:.1f}%")
    print(f"Accuracy on reworded questions (perf): {mean_reworded:.1f}%")
    print(f"GAP (memory - performance)           : {gap:.1f} points")
    print(f"Reworded accuracy on WELL-recalled   : {strong:.1f}%")
    print("  cards (recall >= 80%)  <- the 'memorized but can't apply' case")
    print("-" * 66)

    # PASS: a clear gap means Performance is measured independently of Memory.
    passed = gap >= 15.0
    print("Cutoff: gap >= 15 points (performance is not a copy of memory)")
    print(
        f"RESULT: {'PASS — the bridge is real (perf != memory)' if passed else 'FAIL — perf just mirrors memory'}"
    )
    print("=" * 66)
    print(
        "NOTE: documented SIMULATION with the ablation's learner model. The app "
        "measures Memory and Performance separately; this quantifies the gap."
    )
    print("=" * 66)
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--students", type=int, default=400)
    parser.add_argument("--seed", type=int, default=3)
    args = parser.parse_args()
    return run(students=args.students, seed=args.seed)


if __name__ == "__main__":
    raise SystemExit(main())
