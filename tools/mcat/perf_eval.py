# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Performance-model evaluation for MCAT Speedrun.

The performance model measures a student's exam-style ability from their
first-answer correctness (with a Wilson interval), which drives the Performance
score and the readiness mapping. This checks the model on HELD-OUT exam-style
questions: from a student's answered ("seen") questions, how accurately does it
predict their accuracy on questions it has NOT seen, and does its 95% interval
actually contain the truth ~95% of the time?

Reported:
  - held-out prediction error (MAE) vs. a base-rate baseline (predict the global
    average accuracy for everyone),
  - correlation between the model's estimate and true ability (resolution),
  - Wilson 95% interval coverage of the true ability (interval honesty).

METHOD (documented SIMULATION): students have a true exam-style ability; each
question is answered correct with that probability (plus small per-question
difficulty noise). We split each student's questions into a seen set (fit) and a
held-out set (test). The model's estimate is the seen-set accuracy; the baseline
is the global mean. Reproducible; a real question bank + real answers would
strengthen it.

    PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/perf_eval.py
    (pure stdlib; no backend or network needed)
"""

from __future__ import annotations

import argparse
import math
import random
import statistics

ABILITY_MEAN = 0.55
ABILITY_SPREAD = 0.15
DIFFICULTY_NOISE = 0.06  # per-question wobble around the student's ability


def wilson(k: int, n: int, z: float = 1.96) -> tuple[float, float]:
    if n == 0:
        return (0.0, 1.0)
    p = k / n
    denom = 1 + z * z / n
    center = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return (center - half, center + half)


def run(students: int = 600, seen: int = 40, heldout: int = 25, seed: int = 5) -> int:
    rng = random.Random(seed)
    abilities: list[float] = []
    seen_acc: list[float] = []
    held_acc: list[float] = []
    covered = 0

    for _ in range(students):
        theta = min(0.95, max(0.2, rng.gauss(ABILITY_MEAN, ABILITY_SPREAD)))
        abilities.append(theta)

        def answer() -> int:
            p = min(0.99, max(0.01, theta + rng.gauss(0.0, DIFFICULTY_NOISE)))
            return 1 if rng.random() < p else 0

        seen_correct = sum(answer() for _ in range(seen))
        held_correct = sum(answer() for _ in range(heldout))
        seen_acc.append(seen_correct / seen)
        held_acc.append(held_correct / heldout)

        lo, hi = wilson(seen_correct, seen)
        if lo <= theta <= hi:
            covered += 1

    global_mean = statistics.fmean(seen_acc)
    # MAE of predicting each student's held-out accuracy.
    model_mae = statistics.fmean(
        abs(seen_acc[i] - held_acc[i]) for i in range(students)
    )
    base_mae = statistics.fmean(abs(global_mean - held_acc[i]) for i in range(students))
    coverage = covered / students

    # Pearson correlation between the model estimate and true ability (resolution).
    mp = statistics.fmean(seen_acc)
    mt = statistics.fmean(abilities)
    cov = statistics.fmean(
        (seen_acc[i] - mp) * (abilities[i] - mt) for i in range(students)
    )
    corr = cov / (statistics.pstdev(seen_acc) * statistics.pstdev(abilities))

    print("=" * 66)
    print("MCAT Speedrun — Performance-model held-out evaluation")
    print("=" * 66)
    print(
        f"Students: {students} · seen/held-out per student: {seen}/{heldout} "
        f"exam-style items"
    )
    print("-" * 66)
    print(f"{'metric':<40}{'model':>12}{'baseline':>12}")
    print(
        f"{'held-out accuracy MAE':<40}{model_mae * 100:>11.1f}%"
        f"{base_mae * 100:>11.1f}%"
    )
    print(f"{'estimate vs. true ability (Pearson r)':<40}{corr:>12.2f}{'—':>12}")
    print(f"{'Wilson 95% interval coverage':<40}{coverage * 100:>11.1f}%{'—':>12}")
    print("-" * 66)

    passed = model_mae < base_mae - 0.01 and 0.92 <= coverage <= 0.98
    print(
        "Cutoff: held-out MAE beats the base-rate baseline AND the 95% interval "
        "covers the truth 92-98% of the time"
    )
    print(
        f"RESULT: {'PASS — performance model generalizes + interval is honest' if passed else 'FAIL'}"
    )
    print("=" * 66)
    print(
        "NOTE: documented SIMULATION (per-student ability). Reproducible harness; "
        "a real held-out question bank would strengthen it."
    )
    print("=" * 66)
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--students", type=int, default=600)
    parser.add_argument("--seen", type=int, default=40)
    parser.add_argument("--heldout", type=int, default=25)
    parser.add_argument("--seed", type=int, default=5)
    args = parser.parse_args()
    return run(
        students=args.students, seen=args.seen, heldout=args.heldout, seed=args.seed
    )


if __name__ == "__main__":
    raise SystemExit(main())
