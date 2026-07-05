# MCAT Speedrun — Study-feature ablation (the "three builds")

**Feature under test:** the **memory→performance bridge** — MCAT Speedrun trains
with exam-style **application questions** (confidence rating + delayed second-pass
reasoning), not just flashcards.

**Hypothesis (one sentence):** at equal study time, practicing application
questions produces higher accuracy on *new* application questions than flashcards
alone — even if flashcards match or beat it on raw recall.

**How we'd know it failed:** if the full app does **not** beat vanilla Anki on
held-out application accuracy at equal study time, or if turning the feature off
does **not** erase the gain (i.e. the app just wins because of more cards or more
reviews, not the feature).

Reproduce:

```
PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/ablation.py
```

## The three builds (same held-out questions, same study-time budget)

1. **Full app** — MCAT Speedrun: study time split between flashcards **and**
   application practice.
2. **Feature OFF (ablation)** — MCAT Speedrun with application practice removed →
   flashcards only.
3. **Vanilla Anki** — the unmodified Anki this project forked from: flashcards /
   spaced repetition only (no application-question mode).

Comparing **1 vs 2** isolates the feature; comparing **1 vs 3** asks whether the
whole app beats plain Anki; **2 vs 3** is the control (with the feature off, the
app should behave like plain Anki, proving the gain isn't from cards or volume).

## Method — a documented simulation

This is a **mechanism simulation**, not a human trial (there was no time for a
multi-week study before the deadline). Every assumption is stated so the result
is reproducible and can be argued with:

- Each of 60 topics has two latent abilities, `recall` and `appSkill`, seeded
  from a per-student prior.
- A **flashcard review** raises `recall` (diminishing returns); it does **not**
  raise `appSkill`. `appSkill` starts at a small innate-transfer baseline
  (`APPSKILL0 = 0.10`).
- An **application question** raises `appSkill` (and reinforces `recall` a
  little). Application questions cost far more time than flashcards
  (90 s vs 8 s).
- **The crux:** answering a new application item needs *both* memory and
  application skill: `P(correct) = 0.25 + 0.75 · (recall · appSkill)`. Recall
  items only need memory: `P = 0.10 + 0.90 · recall`. This encodes the
  "I memorized the fact but can't work the passage" trap.
- 400 simulated students, **paired** across the three builds (same starting
  ability per student). The post-test is a *finite* held-out item set (2
  application + 2 recall items per topic), so scores are **sampled** — the ±
  values are real 95% CIs. Equal study time = 5 h per build.

## Results

| build              | application accuracy | recall accuracy |
| ------------------ | -------------------: | --------------: |
| 1. Full app        |         **39.6% ±0.5** |      76.7% ±0.4 |
| 2. Feature OFF     |           31.6% ±0.4 |      88.7% ±0.3 |
| 3. Vanilla Anki    |           31.6% ±0.4 |    **88.7% ±0.3** |

- **Application lift, full vs vanilla Anki: +8.0 points.**
- **Application lift, full vs feature-off: +8.0 points.**
- **Feature-off vs vanilla Anki: 0.0 points** (control behaves as expected).
- **Recall trade-off: vanilla Anki beats the full app by +12.0 points.**

**Verdict: PASS** — the bridge earns its keep. The application gain tracks the
one feature we toggled (feature-off collapses to plain Anki), so it isn't an
artifact of better cards or more reviews.

### Sensitivity

The conclusion is not an artifact of one parameter. Varying the innate
flashcard→application transfer baseline, the application lift (full − Anki) is:

| innate transfer `appSkill0` | 0.05 | 0.10 | 0.20 | 0.35 |
| --------------------------- | ---: | ---: | ---: | ---: |
| application lift (pts)       | +8.9 | +8.0 | +5.8 | +3.0 |

As you'd expect, the feature matters most when memorization transfers *least* to
application (the realistic MCAT regime), and shrinks as transfer approaches 1.

## Honest reporting (what didn't work / the cost)

- **Raw recall is a real trade-off, not a free win.** At equal time the full app
  spends less time on pure memorization, so its recall post-test is ~12 points
  *below* vanilla Anki. The product is explicitly making that trade: a little
  less rote recall for materially better application — which is the exam skill
  that counts. We report both numbers rather than hiding the recall cost.
- **This is a simulation, not a human study.** It demonstrates the designed
  mechanism and provides a reproducible harness; it does **not** prove the effect
  size in real learners. The honest next step is a small user study (even n≈5,
  three sessions, one post-test) to sanity-check the direction and magnitude.
- The absolute application numbers depend on the learner-model constants above;
  the *relative* ordering (full > feature-off ≈ Anki on application; Anki ≥ full
  on recall) is what the study is about and is stable across the sensitivity
  sweep.
