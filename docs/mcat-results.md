# MCAT Speedrun — Results report

Every claim below is backed by a re-runnable script with a **pre-declared
pass/fail cutoff**. Held-out gold sets are never shown to the models. AI evals hit
a live model, so figures vary slightly run-to-run but clear the cutoffs; the
model/study evals are deterministic given the seed.

## Reproduce everything

```
# Models & study evidence (deterministic, no key needed)
PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/ablation.py
PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/calibration.py
PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/perf_eval.py
PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/paraphrase_test.py
PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/leakage_check.py
PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/benchmark.py

# AI features (need OPENAI_API_KEY or the gitignored key file)
PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/eval_reasoning.py
PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/eval_coach.py
PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/eval_cars.py
PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/eval_injection.py

# Engine parity + integrity
just test-rust        # 13 mcat_core tests
just test-py          # pylib MCAT integration + scoring parity tests
```

## Scoreboard

| Area | What it checks | Result | Beats baseline? | Doc |
| --- | --- | --- | --- | --- |
| **Study feature (ablation)** | application practice vs flashcards-only vs vanilla Anki, equal time | **+8.0 pts** application; feature-off ≈ Anki | yes (vs Anki & feature-off) | `mcat-ablation.md` |
| **Memory calibration** | predicted vs actual recall | ECE **0.6%**, Brier 0.123 | yes (vs base-rate 0.130) | `mcat-calibration.md` |
| **Performance model** | predicts held-out question accuracy | MAE **9.7%**, r 0.89, 94.2% coverage | yes (vs 13.9%) | `mcat-performance-eval.md` |
| **Paraphrase test (7d)** | recall on card vs reworded-question accuracy | recall 88% vs perf **40%** = **48-pt gap** | perf isn't a copy of memory | `tools/mcat/paraphrase_test.py` |
| **AI reasoning grader** | labels student reasoning sound/…/flawed | **100%** exact-label | yes (vs 55% keyword) | `mcat-ai-note.md` |
| **AI study coach** | picks the best next action | **100%** focus | yes (vs 75% rule) | `mcat-ai-note.md` |
| **AI CARS debate** | grounded, engages, doesn't capitulate | all cutoffs met | yes (vs canned) | `mcat-ai-note.md` |
| **AI prompt-injection** | resists hidden-text source attacks | **100%** resist / **0%** leak | yes (vs 86%/14% undefended) | `mcat-ai-note.md` |
| **Sync conflicts** | offline same-card merge | correct by construction | — | `mcat-sync.md` |

## Models

One page each for the Memory, Performance and Readiness models — including the
give-up rule and the honesty rule — is in `docs/mcat-models.md`. All three run in
the one shared Rust engine, so desktop and iOS produce identical numbers.

## Honest reporting — what didn't work / the costs

- **The bridge trades raw recall for application.** At equal study time vanilla
  Anki beats the full app on the *recall* post-test by ~12 points; the app
  deliberately spends some of that time on application practice, which is the exam
  skill that counts. We report both numbers, not just the flattering one.
- **The model/study evals are simulations, not human trials.** The ablation,
  calibration and performance evals use documented learner models with stated
  assumptions and sensitivity sweeps. They demonstrate the mechanisms and give
  reproducible harnesses; they do **not** prove effect sizes in real students. The
  honest next step for each is real data (a small user study; a real accumulated
  review log; a real held-out AAMC-style bank) — each script already accepts real
  inputs.
- **Memory calibration is thin at the low end.** Spaced repetition rarely lets
  recall fall below ~60%, so the lowest reliability bins are sparse and noisy.
- **The CARS-debate and coach evals call a live model**, so exact numbers drift
  run-to-run; the cutoffs (not the exact figures) are the claim.
- **Readiness abstains a lot early on** — by design. Until there's enough
  evidence it shows *no* number rather than a fake one; a broad diagnostic only
  unlocks a clearly-labeled low-confidence range.
