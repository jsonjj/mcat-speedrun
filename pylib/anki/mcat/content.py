# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""MCAT content-pack format and seed-deck loader.

A content pack is a JSON document describing memory cards, performance
questions and CARS passages. The loader turns each item into a real Anki note
(tagged per `schema`) so it participates in scheduling, search and sync.

This is the seam where real, licensed MCAT content drops in later: produce a
content pack in this format and call `load_content_pack`. Until then,
`load_seed_deck` installs a small authored (non-AAMC) scaffold so the whole
product loop works end to end.

Content-pack item shapes
------------------------
memory:      {kind, section, topic_ids, difficulty, source_id, front, back,
              reasoning?, ai_ready?}
performance: {kind, section, topic_ids, difficulty, source_id, question,
              choices{A..E}, correct, explanation?, skill?, ai_ready?}
cars:        {kind, section, topic_ids, difficulty, source_id, passage,
              author_claim, debate_prompts[], skill_type?, ai_ready?}
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import TYPE_CHECKING, Any

from anki.mcat import schema

if TYPE_CHECKING:
    import anki.collection
    import anki.decks

_DATA_DIR = Path(__file__).with_name("data")
_SEED_PATH = _DATA_DIR / "seed_deck.json"
# The primary content pack. Replace this file with a full canonical export (same
# format) to load all real MCAT content; everything else is wired to consume it.
_CONTENT_PACK_PATH = _DATA_DIR / "content_pack_v1.json"
# Dedicated CARS debate passages (Student-vs-Author mode), kept separate from
# the multiple-choice CARS questions that live in the main content pack.
_CARS_DEBATES_PATH = _DATA_DIR / "cars_debates.json"


def load_seed_deck(col: anki.collection.Collection) -> dict[str, int]:
    """Install the scaffold seed deck. Returns counts per kind."""
    data = json.loads(_SEED_PATH.read_text(encoding="utf-8"))
    return load_content_pack(col, data)


def load_default_content(col: anki.collection.Collection) -> dict[str, int]:
    """Install the primary content pack (real MCAT content when present).

    Falls back to the scaffold seed deck if the content pack file is missing.
    """
    if _CONTENT_PACK_PATH.exists():
        data = json.loads(_CONTENT_PACK_PATH.read_text(encoding="utf-8"))
        return load_content_pack(col, data)
    return load_seed_deck(col)


# Bump when the bundled pack's MEMORY flashcards change, so existing
# collections re-import them (performance + CARS are left untouched).
CONTENT_VERSION = 2
VERSION_KEY = "mcat:content_version"


def ensure_current(col: anki.collection.Collection) -> dict[str, Any]:
    """Re-import the memory flashcards if the bundled pack changed since the last
    import. Only touches memory cards; performance + CARS are left as-is."""
    try:
        installed = int(col.get_config(VERSION_KEY, 1) or 1)
    except (TypeError, ValueError):
        installed = 1
    if installed >= CONTENT_VERSION:
        return {"reloaded": False}
    count = reload_memory(col)
    col.set_config(VERSION_KEY, CONTENT_VERSION)
    return {"reloaded": True, "memory": count}


def reload_memory(col: anki.collection.Collection) -> int:
    """Replace ALL MCAT memory notes with the pack's current memory items."""
    if not _CONTENT_PACK_PATH.exists():
        return 0
    data = json.loads(_CONTENT_PACK_PATH.read_text(encoding="utf-8"))
    new_items = [it for it in data.get("items", []) if it.get("kind") == "memory"]
    if not new_items:
        return 0

    import anki.notes

    schema.ensure_mcat_notetypes(col)
    existing = [
        anki.notes.NoteId(n)
        for n in col.find_notes(f'"note:{schema.NOTETYPE_MEMORY}"')
    ]
    if existing:
        col.remove_notes(existing)
    deck_id = col.decks.id(data.get("deck", schema.MCAT_DECK_NAME))
    assert deck_id is not None
    for item in new_items:
        _add_memory(col, deck_id, item)
    return len(new_items)


def load_cars_debates(col: anki.collection.Collection) -> dict[str, int]:
    """Install dedicated CARS debate passages, if the file is present."""
    if not _CARS_DEBATES_PATH.exists():
        return {"memory": 0, "performance": 0, "cars": 0}
    data = json.loads(_CARS_DEBATES_PATH.read_text(encoding="utf-8"))
    return load_content_pack(col, data)


def cars_enrichment(passage: str) -> dict[str, Any]:
    """Model answers + per-prompt skills for a CARS passage (matched by text).

    Kept out of the note fields so existing decks pick it up without a notetype
    migration; returns {} when the passage isn't in the bundled debate set.
    """
    if not _CARS_DEBATES_PATH.exists() or not passage:
        return {}
    data = json.loads(_CARS_DEBATES_PATH.read_text(encoding="utf-8"))
    target = passage.strip()
    for item in data.get("items", []):
        if item.get("passage", "").strip() == target:
            return {
                "strong_rebuttal": item.get("strong_rebuttal", ""),
                "strong_defense": item.get("strong_defense", ""),
                "prompt_skills": item.get("prompt_skills", []),
            }
    return {}


def pack_topic_sets() -> tuple[dict[str, set[str]], dict[str, set[str]]]:
    """(memory_topics, performance_topics) per section from the content pack.

    Used to compute topic coverage identically to the iOS app (which reads the
    same bundled pack), so both platforms report the same coverage %.
    """
    mem: dict[str, set[str]] = {}
    perf: dict[str, set[str]] = {}
    if not _CONTENT_PACK_PATH.exists():
        return mem, perf
    data = json.loads(_CONTENT_PACK_PATH.read_text(encoding="utf-8"))
    for item in data.get("items", []):
        section = item.get("section")
        if not section:
            continue
        topics = item.get("topic_ids", []) or []
        if item.get("kind") == "memory":
            mem.setdefault(section, set()).update(topics)
        elif item.get("kind") == "performance":
            perf.setdefault(section, set()).update(topics)
    return mem, perf


def load_content_pack(
    col: anki.collection.Collection, data: dict[str, Any]
) -> dict[str, int]:
    """Create notes from a content pack. Returns counts per kind."""
    schema.ensure_mcat_notetypes(col)
    deck_name = data.get("deck", schema.MCAT_DECK_NAME)
    deck_id = col.decks.id(deck_name)
    assert deck_id is not None

    counts = {"memory": 0, "performance": 0, "cars": 0}
    for item in data.get("items", []):
        kind = item.get("kind")
        if kind == "memory":
            _add_memory(col, deck_id, item)
        elif kind == "performance":
            _add_performance(col, deck_id, item)
        elif kind == "cars":
            _add_cars(col, deck_id, item)
        else:
            continue
        counts[kind] += 1
    return counts


def _join_topics(item: dict[str, Any]) -> str:
    return ", ".join(item.get("topic_ids", []))


def _add_memory(
    col: anki.collection.Collection, deck_id: anki.decks.DeckId, item: dict[str, Any]
) -> None:
    nt = col.models.by_name(schema.NOTETYPE_MEMORY)
    assert nt is not None
    note = col.new_note(nt)
    note["Front"] = item.get("front", "")
    note["Back"] = item.get("back", "")
    note["TopicIds"] = _join_topics(item)
    note["Section"] = item.get("section", "")
    note["SourceId"] = item.get("source_id", "scaffold")
    note["Reasoning"] = item.get("reasoning", "")
    note["AiReady"] = "true" if item.get("ai_ready") else ""
    note.tags = schema.build_tags(
        section=item["section"],
        topic_ids=item.get("topic_ids", []),
        card_type=schema.CARD_TYPE_MEMORY,
        difficulty=int(item.get("difficulty", 3)),
        source_id=item.get("source_id", "scaffold"),
        mode=schema.MODE_MEMORY,
        ai_ready=bool(item.get("ai_ready")),
    )
    col.add_note(note, deck_id)


def _add_performance(
    col: anki.collection.Collection, deck_id: anki.decks.DeckId, item: dict[str, Any]
) -> None:
    nt = col.models.by_name(schema.NOTETYPE_PERFORMANCE)
    assert nt is not None
    choices = item.get("choices", {})
    note = col.new_note(nt)
    note["Question"] = item.get("question", "")
    note["ChoiceA"] = choices.get("A", "")
    note["ChoiceB"] = choices.get("B", "")
    note["ChoiceC"] = choices.get("C", "")
    note["ChoiceD"] = choices.get("D", "")
    note["ChoiceE"] = choices.get("E", "")
    note["CorrectChoice"] = item.get("correct", "")
    note["TopicIds"] = _join_topics(item)
    note["Section"] = item.get("section", "")
    note["SourceId"] = item.get("source_id", "scaffold")
    note["Explanation"] = item.get("explanation", "")
    note["Reasoning"] = item.get("skill", "")
    note["AiReady"] = "true" if item.get("ai_ready") else ""
    note.tags = schema.build_tags(
        section=item["section"],
        topic_ids=item.get("topic_ids", []),
        card_type=schema.CARD_TYPE_PERFORMANCE,
        difficulty=int(item.get("difficulty", 3)),
        source_id=item.get("source_id", "scaffold"),
        mode=schema.MODE_PERFORMANCE,
        ai_ready=bool(item.get("ai_ready")),
    )
    col.add_note(note, deck_id)


def _add_cars(
    col: anki.collection.Collection, deck_id: anki.decks.DeckId, item: dict[str, Any]
) -> None:
    nt = col.models.by_name(schema.NOTETYPE_CARS)
    assert nt is not None
    note = col.new_note(nt)
    note["Passage"] = item.get("passage", "")
    note["AuthorClaim"] = item.get("author_claim", "")
    note["DebatePrompts"] = json.dumps(item.get("debate_prompts", []))
    note["SkillType"] = item.get("skill_type", "")
    note["Section"] = schema.SECTION_CARS
    note["SourceId"] = item.get("source_id", "scaffold")
    note["AiReady"] = "true" if item.get("ai_ready") else ""
    note.tags = schema.build_tags(
        section=schema.SECTION_CARS,
        topic_ids=item.get("topic_ids", []),
        card_type=schema.CARD_TYPE_PERFORMANCE,
        difficulty=int(item.get("difficulty", 3)),
        source_id=item.get("source_id", "scaffold"),
        mode=schema.MODE_DEBATE,
        ai_ready=bool(item.get("ai_ready")),
    )
    col.add_note(note, deck_id)
