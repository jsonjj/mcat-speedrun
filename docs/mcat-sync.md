# MCAT Speedrun — Sync & conflict handling

**Guarantee:** if both devices review the same card offline, the merge is correct
and no review is lost or double-counted. This is true *by construction*, not by
picking a winner.

## The model: event logs, not mutable state

The synced state is **two append-only event logs** in the shared engine
(`rslib/src/mcat_core`):

- `reviews` — one record per graded flashcard `{id, card_key, section, ts, rating}`
- `attempts` — one record per exam-style answer `{id, section, question_key, ts,
  first_correct, batch_id}`

Every event carries a **globally-unique id** (a UUID minted on the device). All
derived state — per-card FSRS schedule, the three scores — is **recomputed by
replaying the logs**. Nothing mutable is synced, so there is nothing to overwrite.

## The merge: replay-union (a grow-only set / CRDT)

`McatState::merge` folds another device's logs in by:

1. **Union by event id**, discarding duplicates (an event already present is
   ignored), then
2. **sorting by `(ts, id)`** for a deterministic replay order.

Because it's a union of an append-only set keyed by unique id, the merge is
**idempotent, commutative, and associative** — pulling the same log twice, or in
either order, yields the same state. That's the CRDT property that makes it
conflict-free: there is never a "winner" to choose.

## Offline → reconnect

Each device appends events locally while offline. On reconnect it pulls the other
device's full log from Firestore (`mcatLogDesktop` / `mcatLogIos`), unions it in,
and recomputes. Nothing is lost (all events are kept) and nothing is
double-counted (dedup by id).

## The same-card offline case (the hard one)

If **both** devices review the *same card* while offline, they produce **two
different events** (different ids, different timestamps). The union keeps **both**;
replaying them in timestamp order applies both reviews to that card's FSRS state,
exactly as if they'd happened on one device in that order. No review is dropped,
none is counted twice, and no arbitrary "last write wins" choice is made.

## Tested

`rslib/src/mcat_core/tests.rs`:

- `merge_is_union_by_event_id` — duplicates dedup; order is `(ts, id)`.
- `merge_is_idempotent` — re-pulling the same log doesn't double-count.
- `review_syncs_and_reschedules_across_devices` — a review on device A reschedules
  the card on device B after merge; an untouched card stays due.
- Python parity: `pylib/tests/test_mcat.py::test_scores_combine_remote_device_logs`.

## Roadmap-progress sync

Daily roadmap completion is a separate, owner-scoped, **union** of completed block
keys per device (`completedBlocksDesktop` / `completedBlocksIos`), date-scoped to
today, so finishing a block on either device never wipes the other's progress.
