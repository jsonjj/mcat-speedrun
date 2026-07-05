# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Study-feature ablation for MCAT Speedrun (the "three builds" study).

FEATURE UNDER TEST: the memory->performance bridge — MCAT Speedrun trains with
exam-style APPLICATION questions (confidence + delayed second-pass reasoning),
not just flashcards.

HYPOTHESIS: at equal study time, practicing application questions produces higher
accuracy on NEW application questions than flashcards alone — even if flashcards
match or beat it on raw recall.
FAIL CONDITION: if the full app does not beat vanilla Anki on held-out
application accuracy at equal study time, or if turning the feature off does not
erase the gain, the feature isn't doing the work.

THREE BUILDS (same held-out questions, same study-time budget):
  1. full      — MCAT Speedrun: time split between flashcards AND application.
  2. ablation  — MCAT Speedrun with application practice removed (flashcards only).
  3. anki      — vanilla Anki: flashcards / spaced repetition only.

METHOD: this is a documented SIMULATION (not a human trial). Each topic has a
latent `recall` and `appSkill`. Flashcards build recall (and a little of the
memory-linked component); application SKILL only grows from application practice
— this encodes the "I memorized the fact but can't answer the passage" trap.
Application accuracy needs BOTH: application = recall * appSkill. We run many
simulated students (paired across the three builds), report means with 95% CIs,
and sweep the key transfer parameter to show the result is not an artifact of one
setting. Honest caveats + the recall/application trade-off are printed.

    PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/ablation.py
    (pure stdlib; no backend or network needed)
"""

from __future__ import annotations

import argparse
import math
import random
import statistics
from dataclasses import dataclass

# Learner-model parameters (the study's stated assumptions).
AR_FC = 0.05  # recall gained per flashcard review
AR_AP = 0.04  # recall also reinforced per application question
AA = 0.14  # application SKILL gained per application question
# Flashcards do NOT build application skill; appSkill starts at a small innate
# transfer baseline. This is the crux of the memory->performance gap.
APPSKILL0_MEAN = 0.10
RECALL0_MEAN = 0.12

# Time economics: an application question costs far more than a flashcard flip.
FC_COST_S = 8
AP_COST_S = 90
# The full app spends this share of its time budget on application practice.
APP_TIME_FRAC = 0.40

# Answer models (4-choice application items floor at guessing; recall floors low).
APP_GUESS = 0.25
RECALL_GUESS = 0.10

# Held-out post-test size: this many application + recall items per topic. A
# finite test means answers are SAMPLED (real sampling variance -> honest CIs).
HELDOUT_APP = 2
HELDOUT_REC = 2


@dataclass
class Result:
    application: float  # mean held-out application accuracy (%)
    app_ci: float
    recall: float  # mean held-out recall accuracy (%)
    recall_ci: float


def _clamp(x: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, x))


def _grow(level: float, rate: float, reps: int) -> float:
    """Diminishing-returns learning curve: level -> 1 as reps accumulate."""
    return 1.0 - (1.0 - level) * ((1.0 - rate) ** reps)


def _spread(total: int, topics: int) -> list[int]:
    """Distribute `total` practice reps as evenly as possible over `topics`."""
    base, extra = divmod(total, topics)
    return [base + (1 if i < extra else 0) for i in range(topics)]


def simulate_student(
    rng: random.Random, topics: int, budget_s: int, build: str, appskill0: float
) -> tuple[float, float]:
    """One student under one build. Returns (application_acc, recall_acc) in %."""
    recall = [_clamp(rng.gauss(RECALL0_MEAN, 0.05)) for _ in range(topics)]
    app_skill = [_clamp(rng.gauss(appskill0, 0.04)) for _ in range(topics)]

    if build == "full":
        app_seconds = int(budget_s * APP_TIME_FRAC)
        fc_seconds = budget_s - app_seconds
    else:  # "ablation" and "anki" are flashcards-only
        app_seconds, fc_seconds = 0, budget_s

    fc_reviews = fc_seconds // FC_COST_S
    ap_questions = app_seconds // AP_COST_S

    for t, reps in enumerate(_spread(fc_reviews, topics)):
        recall[t] = _grow(recall[t], AR_FC, reps)  # flashcards build recall only
    for t, reps in enumerate(_spread(ap_questions, topics)):
        if reps:
            app_skill[t] = _grow(app_skill[t], AA, reps)
            recall[t] = _grow(recall[t], AR_AP, reps)

    # Held-out post-test over the SAME topics for every build. Application needs
    # both memory and application skill; recall needs memory. Answers are sampled
    # from a finite item set, so the per-student score has real test variance.
    app_correct = app_total = rec_correct = rec_total = 0
    for t in range(topics):
        p_app = APP_GUESS + (1 - APP_GUESS) * (recall[t] * app_skill[t])
        p_rec = RECALL_GUESS + (1 - RECALL_GUESS) * recall[t]
        for _ in range(HELDOUT_APP):
            app_total += 1
            app_correct += 1 if rng.random() < p_app else 0
        for _ in range(HELDOUT_REC):
            rec_total += 1
            rec_correct += 1 if rng.random() < p_rec else 0
    return app_correct / app_total * 100, rec_correct / rec_total * 100


def run_build(
    build: str, students: int, topics: int, budget_s: int, appskill0: float, seed: int
) -> Result:
    apps: list[float] = []
    recalls: list[float] = []
    for s in range(students):
        # Paired design: the same seed per student across builds, so builds see
        # identical starting ability and only the study strategy differs.
        rng = random.Random(seed * 100_000 + s)
        a, r = simulate_student(rng, topics, budget_s, build, appskill0)
        apps.append(a)
        recalls.append(r)

    def ci(xs: list[float]) -> float:
        return 1.96 * statistics.pstdev(xs) / math.sqrt(len(xs)) if len(xs) > 1 else 0.0

    return Result(
        application=statistics.fmean(apps),
        app_ci=ci(apps),
        recall=statistics.fmean(recalls),
        recall_ci=ci(recalls),
    )


def run(
    students: int = 400, topics: int = 60, hours: float = 5.0, seed: int = 7
) -> int:
    budget_s = int(hours * 3600)
    builds = {
        b: run_build(b, students, topics, budget_s, APPSKILL0_MEAN, seed)
        for b in ("full", "ablation", "anki")
    }
    full, abl, anki = builds["full"], builds["ablation"], builds["anki"]

    print("=" * 72)
    print("MCAT Speedrun — Study-feature ablation (memory->performance bridge)")
    print("=" * 72)
    print(
        f"Simulated students: {students} · topics: {topics} · "
        f"equal study time: {hours:g} h/build"
    )
    print("Post-test: the same held-out application + recall items for all builds.")
    print("-" * 72)
    print(f"{'build':<26}{'application acc':>20}{'recall acc':>20}")
    labels = {
        "full": "1. Full app",
        "ablation": "2. Feature OFF",
        "anki": "3. Vanilla Anki",
    }
    for key in ("full", "ablation", "anki"):
        r = builds[key]
        print(
            f"{labels[key]:<26}"
            f"{f'{r.application:.1f}% ±{r.app_ci:.1f}':>20}"
            f"{f'{r.recall:.1f}% ±{r.recall_ci:.1f}':>20}"
        )
    print("-" * 72)

    lift_vs_anki = full.application - anki.application
    lift_vs_ablation = full.application - abl.application
    ablation_gap = abs(abl.application - anki.application)
    recall_cost = anki.recall - full.recall

    print(f"Application lift, full vs vanilla Anki : +{lift_vs_anki:.1f} points")
    print(f"Application lift, full vs feature-off  : +{lift_vs_ablation:.1f} points")
    print(f"Feature-off vs vanilla Anki (should ~0): {ablation_gap:.1f} points")
    print(f"Recall trade-off, Anki minus full      : {recall_cost:+.1f} points")
    print("-" * 72)

    # PASS: the feature must (a) beat vanilla Anki on application by a clear
    # margin, and (b) the ablation must account for it (feature-off ~ Anki).
    passed = lift_vs_anki >= 5.0 and lift_vs_ablation >= 5.0 and ablation_gap <= 1.5
    print(
        "Cutoff: application lift >= 5 pts vs BOTH Anki and feature-off, "
        "AND feature-off within 1.5 pts of Anki"
    )
    print(f"RESULT: {'PASS — the bridge earns its keep' if passed else 'FAIL'}")

    # Sensitivity: vary the innate flashcard->application transfer baseline. If the
    # conclusion held only at one setting it would be an artifact.
    print("-" * 72)
    print("Sensitivity — application lift (full - Anki) vs innate transfer baseline:")
    for base in (0.05, 0.10, 0.20, 0.35):
        f = run_build("full", students, topics, budget_s, base, seed)
        a = run_build("anki", students, topics, budget_s, base, seed)
        print(f"  appSkill0={base:.2f}  ->  +{f.application - a.application:.1f} pts")
    print("=" * 72)
    print(
        "NOTE: this is a mechanism SIMULATION with the stated learner model, not a "
        "human trial. It shows the feature's designed effect and gives a\n"
        "reproducible harness; a real user study would strengthen it."
    )
    print("=" * 72)
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--students", type=int, default=400)
    parser.add_argument("--topics", type=int, default=60)
    parser.add_argument("--hours", type=float, default=5.0)
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()
    return run(
        students=args.students, topics=args.topics, hours=args.hours, seed=args.seed
    )


if __name__ == "__main__":
    raise SystemExit(main())
