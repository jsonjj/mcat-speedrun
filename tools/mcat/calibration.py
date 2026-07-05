# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Memory-model calibration for MCAT Speedrun.

The memory model is FSRS — the forgetting curve the shared engine schedules by.
"Calibrated" means: when it predicts ~80% recall, students really recall ~80%.
This checks that on held-out reviews and reports a reliability table, a Brier
score and log loss, the Expected Calibration Error (ECE), and a comparison to a
base-rate baseline (a predictor that always guesses the overall recall rate — it
is calibrated on average but has no resolution). It also writes an SVG
reliability diagram to docs/mcat-calibration.svg.

METHOD (documented SIMULATION, not a human trial): each card has a TRUE stability
and forgetting rate; the model only has a NOISY estimate of the stability (as in
real life). Predicted recall uses the standard FSRS retrievability formula with
the model's estimate; the actual outcome is drawn from the card's TRUE curve.
The estimation noise is what keeps calibration realistic rather than perfect.

    PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/calibration.py
    (pure stdlib; no backend or network needed)
"""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

# FSRS retrievability: R(t) = (1 + FACTOR * t/S) ** DECAY, tuned so R(S) = 0.9.
DECAY = -0.5
FACTOR = 19.0 / 81.0

# Card population + model-estimation noise (the model's stability estimate is off
# by this log-normal factor; true forgetting rate also varies slightly).
MEAN_STABILITY_DAYS = 12.0
STABILITY_SPREAD = 0.8
EST_NOISE = 0.35
DECAY_HETERO = 0.06


def retrievability(t_days: float, stability: float, decay: float = DECAY) -> float:
    return (1.0 + FACTOR * t_days / stability) ** decay


def simulate_reviews(
    cards: int, reviews_per_card: int, seed: int
) -> list[tuple[float, int]]:
    """Return held-out (predicted_recall, actual_recalled) pairs."""
    rng = random.Random(seed)
    pairs: list[tuple[float, int]] = []
    for _ in range(cards):
        s_true = math.exp(rng.gauss(math.log(MEAN_STABILITY_DAYS), STABILITY_SPREAD))
        s_est = s_true * math.exp(rng.gauss(0.0, EST_NOISE))  # model's noisy guess
        decay_true = DECAY + rng.gauss(0.0, DECAY_HETERO)
        for _ in range(reviews_per_card):
            # Most reviews land near the due time; a realistic chunk are "overdue"
            # (the student fell behind), which populates the low-recall bins.
            if rng.random() < 0.25:
                elapsed = s_est * rng.uniform(1.5, 6.0)
            else:
                elapsed = s_est * math.exp(rng.gauss(0.0, 0.6))
            predicted = retrievability(elapsed, s_est)  # model prediction
            p_true = retrievability(elapsed, s_true, decay_true)  # reality
            actual = 1 if rng.random() < p_true else 0
            pairs.append((min(0.999, max(0.001, predicted)), actual))
    return pairs


def brier(pairs: list[tuple[float, int]]) -> float:
    return sum((p - a) ** 2 for p, a in pairs) / len(pairs)


def log_loss(pairs: list[tuple[float, int]]) -> float:
    return -sum(a * math.log(p) + (1 - a) * math.log(1 - p) for p, a in pairs) / len(
        pairs
    )


def reliability_bins(
    pairs: list[tuple[float, int]], nbins: int = 10
) -> list[tuple[float, float, float, int]]:
    """Per-bin (lo, mean_predicted, observed_rate, count)."""
    buckets: list[list[tuple[float, int]]] = [[] for _ in range(nbins)]
    for p, a in pairs:
        buckets[min(nbins - 1, int(p * nbins))].append((p, a))
    out = []
    for i, b in enumerate(buckets):
        if not b:
            out.append((i / nbins, float("nan"), float("nan"), 0))
            continue
        mp = sum(p for p, _ in b) / len(b)
        obs = sum(a for _, a in b) / len(b)
        out.append((i / nbins, mp, obs, len(b)))
    return out


def ece(bins: list[tuple[float, float, float, int]], total: int) -> float:
    return sum(
        (n / total) * abs(obs - mp)
        for _, mp, obs, n in bins
        if n and not math.isnan(mp)
    )


def write_svg(bins: list[tuple[float, float, float, int]], path: Path) -> None:
    """A reliability diagram: predicted (x) vs observed (y) with the ideal y=x."""
    w = h = 320
    m = 40  # margin
    inner = w - 2 * m

    def sx(v: float) -> float:
        return m + v * inner

    def sy(v: float) -> float:
        return h - m - v * inner

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
        f'font-family="-apple-system,Helvetica,Arial,sans-serif">',
        f'<rect width="{w}" height="{h}" fill="white"/>',
        # axes
        f'<line x1="{m}" y1="{h - m}" x2="{w - m}" y2="{h - m}" stroke="#94a3b8"/>',
        f'<line x1="{m}" y1="{m}" x2="{m}" y2="{h - m}" stroke="#94a3b8"/>',
        # ideal diagonal
        f'<line x1="{sx(0)}" y1="{sy(0)}" x2="{sx(1)}" y2="{sy(1)}" '
        'stroke="#cbd5e1" stroke-dasharray="4 4"/>',
    ]
    pts = [(mp, obs) for _, mp, obs, n in bins if n and not math.isnan(mp)]
    if pts:
        poly = " ".join(f"{sx(mp):.1f},{sy(obs):.1f}" for mp, obs in pts)
        parts.append(
            f'<polyline points="{poly}" fill="none" stroke="#6366f1" stroke-width="2.5"/>'
        )
        for mp, obs in pts:
            parts.append(
                f'<circle cx="{sx(mp):.1f}" cy="{sy(obs):.1f}" r="3.5" fill="#6366f1"/>'
            )
    parts.append(
        f'<text x="{w / 2}" y="{h - 10}" text-anchor="middle" font-size="12" '
        'fill="#475569">Predicted recall</text>'
    )
    parts.append(
        f'<text x="14" y="{h / 2}" text-anchor="middle" font-size="12" fill="#475569" '
        f'transform="rotate(-90 14 {h / 2})">Observed recall</text>'
    )
    parts.append(
        f'<text x="{w / 2}" y="20" text-anchor="middle" font-size="13" '
        'font-weight="bold" fill="#0f172a">FSRS memory calibration</text>'
    )
    parts.append("</svg>")
    path.write_text("\n".join(parts), encoding="utf-8")


def run(cards: int = 4000, reviews_per_card: int = 6, seed: int = 11) -> int:
    pairs = simulate_reviews(cards, reviews_per_card, seed)
    n = len(pairs)
    base_rate = sum(a for _, a in pairs) / n
    fsrs_brier = brier(pairs)
    baseline_brier = brier([(base_rate, a) for _, a in pairs])
    bins = reliability_bins(pairs)
    cal_error = ece(bins, n)

    print("=" * 68)
    print("MCAT Speedrun — Memory-model (FSRS) calibration")
    print("=" * 68)
    print(f"Held-out reviews: {n}  ·  overall recall rate: {base_rate:.1%}")
    print("-" * 68)
    print(f"{'predicted bin':<16}{'predicted':>11}{'observed':>11}{'n':>10}")
    for lo, mp, obs, cnt in bins:
        if not cnt or math.isnan(mp):
            continue
        print(
            f"{f'{lo:.1f}-{lo + 0.1:.1f}':<16}{f'{mp:.1%}':>11}{f'{obs:.1%}':>11}{cnt:>10}"
        )
    print("-" * 68)
    print(f"Brier score (FSRS)     : {fsrs_brier:.4f}   (lower is better)")
    print(f"Brier score (base-rate): {baseline_brier:.4f}   (simpler baseline)")
    print(f"Log loss (FSRS)        : {log_loss(pairs):.4f}")
    print(f"Expected Calib. Error  : {cal_error:.4f}")
    print("-" * 68)

    passed = cal_error <= 0.03 and fsrs_brier < baseline_brier
    print(
        "Cutoff: ECE <= 0.03 (well calibrated) AND Brier beats the base-rate baseline"
    )
    print(f"RESULT: {'PASS — memory model is calibrated' if passed else 'FAIL'}")

    out = Path(__file__).resolve().parents[2] / "docs" / "mcat-calibration.svg"
    write_svg(bins, out)
    print(f"Reliability diagram written to {out.relative_to(out.parents[2])}")
    print("=" * 68)
    print(
        "NOTE: documented SIMULATION with model-estimation noise, not a human "
        "trial. Reproducible harness; real reviews would strengthen it."
    )
    print("=" * 68)
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cards", type=int, default=4000)
    parser.add_argument("--reviews", type=int, default=6)
    parser.add_argument("--seed", type=int, default=11)
    args = parser.parse_args()
    return run(cards=args.cards, reviews_per_card=args.reviews, seed=args.seed)


if __name__ == "__main__":
    raise SystemExit(main())
