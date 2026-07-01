# Rust Engine Change: the MCAT Mastery Query

This is MCAT Speedrun's first real change inside Anki's Rust engine (not just the
Python/Qt UI). It adds a new backend RPC, `MasteryService.GetTopicMastery`, that
aggregates per-topic mastery directly in Rust.

## What it does

For every MCAT topic (discovered from `topic:<id>` tags), it returns:

- content/scheduling counts: total, memory, performance, reviewed, due, mature
  cards, and graded-review count;
- an `avg_retrievability` recall proxy in `[0, 1]`, computed from each reviewed
  card's interval and overdue days (FSRS memory state can refine it later);
- performance evidence pulled from the stored attempts (`mcat:attempts` in the
  collection config): attempt counts, first-answer-correct counts, and
  confidence-calibration counts (certain/guessing, with correct sub-counts);
- a `coverage` status (none / memory-only / performance-only / full).

It also returns collection-wide totals (graded reviews, performance attempts)
used by the readiness abstention rules.

Source: [proto/anki/mastery.proto](../proto/anki/mastery.proto),
[rslib/src/mastery/mod.rs](../rslib/src/mastery/mod.rs),
[rslib/src/mastery/service.rs](../rslib/src/mastery/service.rs).

## Why this belongs in Rust, not Python

1. **It runs over the whole collection.** Aggregating cards + reviews + tags
   per topic is exactly the kind of hot, data-heavy loop that must stay close to
   the SQLite layer. The dashboard refreshes against this on every visit; the
   PRD targets dashboard first-load p95 < 1s and refresh p95 < 500ms on large
   decks. Looping cards in Python (one object per card across the Python/Rust
   bridge) would be the slowest possible path; doing it in Rust avoids thousands
   of cross-language round-trips and reuses the existing search + storage code.
2. **It is the shared-engine path.** The desktop Python UI and the future iOS
   app both reach the same Rust backend. Putting the aggregation in Rust means
   one implementation powers both apps, instead of re-deriving mastery twice.
3. **It composes with collection internals.** It reuses `search_cards`,
   `storage.get_card`/`get_note`, `timing_today`, and the typed `Card`/`Note`
   structs and scheduling enums (`CardType`, `CardQueue`) that are only
   conveniently available inside the crate.

The transparent score _mapping_ (memory/performance/readiness ranges and the
abstention rules) deliberately stays in Python
([pylib/anki/mcat/scoring.py](../pylib/anki/mcat/scoring.py)) so it can iterate
quickly; only the heavy aggregation moved into Rust.

## Upstream files touched

New files (low merge risk - additive):

- `proto/anki/mastery.proto`
- `rslib/src/mastery/mod.rs`, `rslib/src/mastery/service.rs`,
  `rslib/src/mastery/tests.rs`

Modified upstream files (small, localized edits - the lines most likely to
conflict on an upstream merge):

- `rslib/src/lib.rs` - added `pub mod mastery;` to the module list.
- `rslib/proto/src/lib.rs` - added `protobuf!(mastery, "mastery");`.
- `rslib/proto/python.rs` - added `import anki.mastery_pb2` to the generated
  Python backend's import header (the TS generator derives imports
  automatically, so it needed no change).
- `qt/aqt/mediasrv.py` - added `get_topic_mastery` to `exposed_backend_list`
  and `"mcat"` to the SvelteKit page allow-list.

No existing Rust functions were modified, so the change is almost entirely
additive. The dispatch trait and the `_raw`/snake_case bindings are
code-generated from the `.proto`, so no manual wiring of service indices was
needed.

## Future merge difficulty

Low. The only edits to existing files are single-line additions to ordered
lists (module lists, an import header, two allow-lists). The realistic conflict
points on an upstream rebase are:

- the `protobuf!(...)` list in `rslib/proto/src/lib.rs` and the `pub mod`
  list in `rslib/src/lib.rs` (trivial three-way merges);
- the hardcoded import header in `rslib/proto/python.rs` (one line);
- the two lists in `qt/aqt/mediasrv.py`.

All are mechanical. The new module and proto are self-contained, so upstream
changes to scheduling/FSRS would not break compilation; at most they would let
us improve `avg_retrievability` by reading real FSRS memory state.

## Tests / proof

- 3+ Rust unit tests: [rslib/src/mastery/tests.rs](../rslib/src/mastery/tests.rs)
  (coverage classification, section filtering, config-driven performance +
  calibration, and reviewed/mature/retrievability from scheduling state).
- 1 Python integration test calling the RPC end to end, plus proof that undo
  still works and `fix_integrity` reports a healthy collection:
  [pylib/tests/test_mcat.py](../pylib/tests/test_mcat.py).
- The query is read-only, so it cannot corrupt the collection; the integration
  test still exercises an add -> undo cycle around it to confirm.
