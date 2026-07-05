# MCAT Speedrun — Performance-model evaluation

**Model:** the performance model measures a student's exam-style ability from
first-answer correctness (with a **Wilson interval**), which drives the
Performance score and the readiness mapping.

**Question:** from the questions a student has answered, does the model predict
their accuracy on **held-out** (unseen) exam-style questions — and is its stated
interval honest (does the 95% interval really contain the truth ~95% of the
time)?

Reproduce:

```
PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/perf_eval.py
```

## Method (documented simulation)

Students have a true exam-style ability; each question is answered correct with
that probability plus small per-question difficulty noise. Each student's items
are split into a **seen** set (fit) and a **held-out** set (test). The model's
estimate is the seen-set accuracy; the **baseline** predicts the global average
accuracy for everyone. 600 students, 40 seen / 25 held-out items each.

## Results

| metric                                | model | baseline |
| ------------------------------------- | ----: | -------: |
| held-out accuracy MAE                 |  9.7% |    13.9% |
| estimate vs. true ability (Pearson r) |  0.89 |        — |
| Wilson 95% interval coverage          | 94.2% |        — |

**Verdict: PASS.**
- The model predicts unseen-question accuracy with **9.7% MAE, beating the
  base-rate baseline (13.9%)** — it's tracking real per-student ability, not just
  echoing the average.
- **r = 0.89** between the model's estimate and true ability (good resolution).
- **94.2% coverage** for the nominal 95% Wilson interval — the interval the app
  shows is honest (it isn't over- or under-confident).

## Honest notes

- Accuracy is bounded by test length: with only 25 held-out items, even a perfect
  model has irreducible sampling error (~±10%), so 9.7% MAE is near that floor.
- Simulation, not a human study; the honest upgrade is a real held-out AAMC-style
  question bank with real answers. The Wilson-interval machinery evaluated here is
  exactly what ships in the engine.
