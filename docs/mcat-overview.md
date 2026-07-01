# MCAT Speedrun: Architecture Overview

MCAT Speedrun is a brownfield fork of Anki that adds a complete, non-AI (but
AI-ready) MCAT preparation loop on top of Anki's spaced-repetition engine. It
measures three separate things and never blends them:

- **Memory** — can you recall prerequisites now? (Anki/FSRS)
- **Performance** — can you apply them to new exam-style questions?
- **Readiness** — what MCAT range would you likely score today, and how sure?

This document is the map. It complements the engine-change note in
[mcat-mastery-query-note.md](./mcat-mastery-query-note.md).

## How it's layered

```
Svelte pages (ts/routes/mcat/*)            <- dashboard, mini, diagnostic, roadmap, cars
        |  JSON POST /_anki/mcat*
Qt HTTP endpoints (qt/aqt/mcat/endpoints)  <- thin handlers, grading, batch feedback
        |  Python calls
pylib logic (pylib/anki/mcat/*)            <- schema, store, scoring, questions, planner
        |  col._backend.get_topic_mastery / col.* primitives
Rust core (rslib/src/mastery + Anki)       <- Mastery Query aggregation, SQLite, FSRS
```

Nothing calls AI. Every field AI will later use (reasoning text, source ids,
mistake labels, confidence calibration) is already captured.

## Data model (no schema changes)

We use only Anki's existing primitives, so sync, undo and integrity work for
free:

- **Content** = Anki notes/cards using three MCAT notetypes (`MCAT Memory`,
  `MCAT Performance`, `MCAT CARS`), tagged per `pylib/anki/mcat/schema.py`
  (`exam:mcat`, `section:*`, `topic:*`, `card_type:*`, `difficulty:*`,
  `source:*`, `mode:*`, `phase:*`, `ai_ready:*`).
- **Attempts, daily plans, scores, debates** = JSON in the synced collection
  config under `mcat:*` keys (`pylib/anki/mcat/store.py`).

## The Rust engine change

`MasteryService.GetTopicMastery` (`proto/anki/mastery.proto`,
`rslib/src/mastery/`) aggregates per-topic mastery (cards, reviews, FSRS recall
proxy, performance attempts, calibration, coverage) in Rust so the dashboard is
fast on large decks. See the change note for the rationale, tests and merge
risk.

## Scoring (transparent, AI-off)

`pylib/anki/mcat/scoring.py` turns the Mastery Query + attempts into three
score blocks with ranges and **strict abstention**:

- Performance/readiness use a Wilson interval over first-answer correctness,
  mapped onto the 118-132 section scale (472-528 total).
- Readiness abstains until coverage and sample thresholds are met (per section:
  > =40% topic coverage with both a memory and performance item, and >=2
  > performance sets; overall: all four sections plus >=100 graded reviews and
  > =40 performance attempts). A diagnostic exception allows a low-confidence
  > range after a Standard/Best-Estimate diagnostic.

## The learning loop

- **Diagnostic** (Quick/Standard/Best-Estimate) samples all four sections.
- **Daily roadmap** turns exam date + minutes into ordered <=20-min blocks;
  required blocks (in order) earn the streak. Adaptive focus picks a weak
  primary and a smaller secondary section. Full-length cadence is exam-date
  aware; optional free practice unlocks after required work.
- **Mini-MCAT / performance** captures first answer, **confidence**
  (Certain/Leaning/Guessing), and timing. With any wrong answer it shows
  **delayed batch feedback** (count only, no reveal), then a **second pass**
  requiring written reasoning; it stores correctness before/after and a
  non-AI label (`correct_after_retry`, `stayed_confident`, ...).
- **CARS** is a Student-vs-Author debate, not flashcards.

## Adding real content

Produce a content pack in the format documented in
`pylib/anki/mcat/content.py` and load it:

```python
from anki.mcat import content
content.load_content_pack(col, pack_dict)
```

Swap the scaffold taxonomy in `pylib/anki/mcat/data/taxonomy.json` for the
official AAMC outline when available. Keep a `source_id` on every item so
reports and future AI outputs can trace provenance. Do not hardcode
unauthorized scraped official/copyrighted questions.

## Tests and proof

- Rust unit tests: `cargo test -p anki mastery::` (or `just test-rust`).
- Python integration test: `pylib/tests/test_mcat.py` (mastery query end to
  end, plus undo + `fix_integrity`).
- One-command benchmark: `tools/mcat/benchmark.py` (p50/p95/worst for the
  Mastery Query and scoring on a large generated deck).
- Leakage check: `tools/mcat/leakage_check.py` (no duplicate questions, no
  memory-answer leakage into performance explanations).

## Desktop entry points

An **MCAT** menu and a top-toolbar **MCAT** link open the pages
(`qt/aqt/mcat/screens.py`). Pages are served by Anki's mediasrv and reach the
backend via `/_anki/mcat*` (registered in `qt/aqt/mediasrv.py`).

## Deferred (intentionally)

- **iOS companion** (Swift + Rust FFI) and two-way sync — the shared-engine
  path is the Rust backend; this is a separate milestone.
- **AI layer** — plugs into the existing reasoning/source/explanation fields;
  the app must always score with AI off.

## License

This is a fork of Anki and remains under **AGPL-3.0-or-later**. Some Anki
components are BSD-3-Clause; preserve their notices. Credit Anki
(https://apps.ankiweb.net).
