# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Structural validator for MCAT content packs.

Checks the things that would silently corrupt the product if wrong:
- every performance item's `correct` is a key that exists in its `choices`
- sections are valid MCAT section codes
- required fields are present per item kind
- reports counts per kind and per section, and the set of topic ids

Exit code is non-zero if any error is found, so it can gate CI.

Usage:
    PYTHONPATH="pylib:out/pylib" out/pyenv/bin/python tools/mcat/validate_content.py [pack.json ...]
"""

from __future__ import annotations

import json
import sys
from collections import Counter

VALID_SECTIONS = {"bb", "cp", "ps", "cars"}
DEFAULT_PACKS = [
    "pylib/anki/mcat/data/content_pack_v1.json",
    "pylib/anki/mcat/data/cars_debates.json",
    "pylib/anki/mcat/data/seed_deck.json",
]


def validate_pack(path: str) -> tuple[list[str], dict]:
    errors: list[str] = []
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    items = data.get("items", [])
    kinds: Counter = Counter()
    sections: Counter = Counter()
    topic_ids: set[str] = set()

    for i, item in enumerate(items):
        kind = item.get("kind")
        section = item.get("section")
        kinds[kind] += 1
        sections[section] += 1
        for tid in item.get("topic_ids", []):
            topic_ids.add(tid)

        where = f"{path}[{i}] ({kind}/{section})"
        if section not in VALID_SECTIONS:
            errors.append(f"{where}: invalid section {section!r}")

        if kind == "performance":
            choices = item.get("choices", {})
            correct = item.get("correct")
            if not item.get("question"):
                errors.append(f"{where}: missing question")
            if not choices:
                errors.append(f"{where}: missing choices")
            if correct not in choices:
                errors.append(
                    f"{where}: correct={correct!r} is not a choice key {sorted(choices)}"
                )
        elif kind == "memory":
            if not item.get("front") or not item.get("back"):
                errors.append(f"{where}: memory item missing front/back")
        elif kind == "cars":
            if not item.get("passage") or not item.get("author_claim"):
                errors.append(f"{where}: cars item missing passage/author_claim")
            if not item.get("debate_prompts"):
                errors.append(f"{where}: cars item missing debate_prompts")
        else:
            errors.append(f"{where}: unknown kind {kind!r}")

    stats = {
        "path": path,
        "total": len(items),
        "kinds": dict(kinds),
        "sections": dict(sections),
        "topics": len(topic_ids),
    }
    return errors, stats


def main() -> int:
    packs = sys.argv[1:] or DEFAULT_PACKS
    all_errors: list[str] = []
    for path in packs:
        try:
            errors, stats = validate_pack(path)
        except FileNotFoundError:
            print(f"skip (not found): {path}")
            continue
        all_errors += errors
        print(
            f"{stats['path']}: {stats['total']} items, kinds={stats['kinds']}, "
            f"sections={stats['sections']}, distinct topics={stats['topics']}"
        )

    if all_errors:
        print(f"\nVALIDATION FAILED ({len(all_errors)} error(s)):")
        for err in all_errors[:50]:
            print(f"  - {err}")
        return 1
    print("\nValidation passed: all answer keys valid, all items well-formed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
