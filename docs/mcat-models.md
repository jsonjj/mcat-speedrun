# MCAT Speedrun — Model descriptions

Three models answer three different questions. All numbers come from **one shared
Rust engine** (`rslib/src/mcat_core`), so desktop and iOS are byte-identical.
Source of truth: `scoring.rs` (scores) and `fsrs_sched.rs` (scheduling).

---

## 1. Memory model — "can you recall this fact right now?"

**What it is.** Anki's **FSRS** forgetting curve. Each card has a stability `S`;
predicted recall at elapsed time `t` is

```
R(t) = (1 + (19/81)·t/S) ^ (−0.5)      (R(S) = 0.90 by construction)
```

FSRS schedules reviews; grading a card (Again/Hard/Good/Easy) updates `S`.

**The score (Memory Recall).** The % of graded reviews recalled (Good/Easy, i.e.
rating ≥ 3). Per section = `reviews_correct / reviews`; overall = the mean of the
per-section values. Shown with a range band that tightens with evidence: **±18**
under 20 reviews, **±10** under 80, **±5** at 80+.

**Give-up rule.** Abstains for a section with no graded reviews.

**Calibration.** ECE **0.6%**, Brier beats a base-rate baseline — see
`docs/mcat-calibration.md` (`tools/mcat/calibration.py`).

---

## 2. Performance model — "can you answer a new exam-style question with it?"

**What it is.** First-answer correctness on exam-style questions, summarized as a
**Wilson score interval** (z = 1.96) so small samples aren't over-trusted:

```
center = (p̂ + z²/2n) / (1 + z²/n)
margin = z·√(p̂(1−p̂)/n + z²/4n²) / (1 + z²/n)
```

Per section from that section's attempts; overall from all attempts. The point is
`p̂`; the range is the Wilson interval.

**Give-up rule.** Abstains for a section with no attempts.

**Held-out evaluation.** Predicts unseen-question accuracy at **9.7% MAE vs 13.9%
baseline**, r = 0.89 with true ability, and the 95% interval covers the truth
**94.2%** of the time — see `docs/mcat-performance-eval.md`
(`tools/mcat/perf_eval.py`).

---

## 3. Readiness model — "what would you score today, and how sure are we?"

**What it is.** Each section's performance proportion is mapped onto the MCAT
**118–132** section scale by a piecewise-linear anchor curve, then the four
sections are summed to a **472–528** total. The range is the sum of the section
ranges (from the Wilson low/high), so uncertainty propagates end-to-end.

Anchor curve (proportion → section score), interpolated linearly between points:

| proportion | 0.00 | 0.25 | 0.40 | 0.50 | 0.55 | 0.65 | 0.75 | 0.85 | 0.92 | 1.00 |
| ---------- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| score      | 118  | 121  | 123  | 124  | 125  | 127  | 128  | 130  | 131  | 132  |

**The give-up rule (this is the core honesty guarantee).** A full readiness score
is shown **only when all of these hold**:

- **every** section has **coverage ≥ 40%** *and* **≥ 2 performance sets**, and
- **≥ 100 graded reviews** overall, and
- **≥ 40 performance attempts** overall.

Otherwise:
- If a **standard or best-estimate diagnostic** was taken and all four sections
  have at least one attempt, a **low-confidence** range is shown (sum of section
  anchors ±1 per section, clamped to 472–528) and clearly labeled low-confidence.
- Otherwise the app **abstains** — it shows *no* number.

**The honesty rule.** Whenever any score is shown, the app also shows: the
evidence behind it, what data is still missing, how accurate past estimates have
been (calibration), the **range** (never a bare point), and the single best next
action. A confident number without those is a guess in a nice font — so we don't
show one.

---

### Why three separate models

Remembering "mitochondria = powerhouse" (Memory) does not mean you can answer a
cellular-respiration passage (Performance), and neither alone tells you your test
score (Readiness). The **ablation study** (`docs/mcat-ablation.md`) measures the
memory→performance gap directly: at equal study time, application practice adds
**+8 points** of application accuracy over flashcards-only, at a deliberate ~12-
point cost to raw recall.
