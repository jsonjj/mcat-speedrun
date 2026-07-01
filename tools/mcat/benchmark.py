# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""One-command benchmark for the MCAT Speedrun Mastery Query + scoring.

Generates a large MCAT deck, then times the Rust Mastery Query and the Python
scoring layer over many runs, reporting p50 / p95 / worst case.

Usage (from the repo root, after `just build`):

    PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/benchmark.py --cards 4000
"""

from __future__ import annotations

import argparse
import os
import statistics
import tempfile
import time

from anki.collection import Collection
from anki.mcat import content, scoring, store, taxonomy


def build_large_deck(col: Collection, cards: int) -> None:
    tax = taxonomy.load_taxonomy()
    topic_ids = tax.topic_ids()
    items = []
    for i in range(cards):
        topic = topic_ids[i % len(topic_ids)]
        section = topic.split(".")[0]
        if i % 2 == 0:
            items.append(
                {
                    "kind": "memory",
                    "section": section,
                    "topic_ids": [topic],
                    "difficulty": (i % 5) + 1,
                    "source_id": "benchmark",
                    "front": f"Memory prompt {i}",
                    "back": f"Answer {i}",
                }
            )
        else:
            items.append(
                {
                    "kind": "performance",
                    "section": section,
                    "topic_ids": [topic],
                    "difficulty": (i % 5) + 1,
                    "source_id": "benchmark",
                    "question": f"Performance question {i}?",
                    "choices": {"A": "a", "B": "b", "C": "c", "D": "d"},
                    "correct": "B",
                    "explanation": "because b",
                }
            )
    content.load_content_pack(col, {"deck": "MCAT Benchmark", "items": items})


def seed_attempts(col: Collection, n: int) -> None:
    tax = taxonomy.load_taxonomy()
    topic_ids = tax.topic_ids()
    for i in range(n):
        topic = topic_ids[i % len(topic_ids)]
        store.add_attempt(
            col,
            store.new_attempt(
                note_id=None,
                card_id=None,
                section=topic.split(".")[0],
                topic_ids=[topic],
                difficulty=(i % 5) + 1,
                source_id="benchmark",
                mode="performance",
                phase="daily",
                first_choice="B",
                first_correct=(i % 3 != 0),
                confidence="leaning",
                first_time_ms=4000,
                batch_id=f"b{i // 5}",
            ),
        )


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    k = max(0, min(len(ordered) - 1, int(round((pct / 100.0) * (len(ordered) - 1)))))
    return ordered[k]


def time_runs(label: str, fn, runs: int) -> None:  # type: ignore[no-untyped-def]
    timings: list[float] = []
    for _ in range(runs):
        start = time.perf_counter()
        fn()
        timings.append((time.perf_counter() - start) * 1000.0)
    print(
        f"{label:<28} p50={percentile(timings, 50):7.2f}ms  "
        f"p95={percentile(timings, 95):7.2f}ms  "
        f"worst={max(timings):7.2f}ms  mean={statistics.mean(timings):7.2f}ms"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="MCAT Speedrun benchmark")
    parser.add_argument(
        "--cards", type=int, default=2000, help="number of cards to generate"
    )
    parser.add_argument(
        "--attempts", type=int, default=400, help="performance attempts to seed"
    )
    parser.add_argument("--runs", type=int, default=50, help="timed runs")
    args = parser.parse_args()

    fd, path = tempfile.mkstemp(suffix=".anki2")
    os.close(fd)
    os.unlink(path)
    col = Collection(path)
    try:
        print(f"Generating {args.cards} cards and {args.attempts} attempts…")
        t0 = time.perf_counter()
        build_large_deck(col, args.cards)
        seed_attempts(col, args.attempts)
        print(f"Setup took {(time.perf_counter() - t0):.1f}s\n")

        time_runs(
            "MasteryQuery (Rust)", lambda: col._backend.get_topic_mastery(""), args.runs
        )
        time_runs(
            "compute_scores (Python)", lambda: scoring.compute_scores(col), args.runs
        )
    finally:
        col.close()


if __name__ == "__main__":
    main()
