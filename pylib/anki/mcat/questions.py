# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Selecting and serialising MCAT performance questions.

The client never receives the correct answer or explanation during the first
pass: correctness is computed on the backend so that delayed batch feedback and
second-pass reasoning are honest.
"""

from __future__ import annotations

import random
from typing import TYPE_CHECKING, Any

from anki.mcat import schema

if TYPE_CHECKING:
    import anki.collection

_CHOICE_FIELDS = [
    ("A", "ChoiceA"),
    ("B", "ChoiceB"),
    ("C", "ChoiceC"),
    ("D", "ChoiceD"),
    ("E", "ChoiceE"),
]


def performance_note_ids(
    col: anki.collection.Collection,
    *,
    section: str | None = None,
    topic_id: str | None = None,
) -> list[int]:
    """Note ids for MCAT multiple-choice performance questions, optionally filtered.

    Restricted to the MCAT Performance notetype so CARS debate notes (which are
    also tagged card_type:performance) never leak into the multiple-choice flow.
    """
    terms = [
        f'"note:{schema.NOTETYPE_PERFORMANCE}"',
        f'"tag:{schema.TAG_EXAM}"',
    ]
    if section:
        terms.append(f'"tag:{schema.TAG_SECTION_PREFIX}{section}"')
    if topic_id:
        terms.append(f'"tag:{schema.TAG_TOPIC_PREFIX}{topic_id}"')
    query = " ".join(terms)
    return [int(nid) for nid in col.find_notes(query)]


def sample_questions(
    col: anki.collection.Collection,
    *,
    section: str | None,
    count: int,
    seed: int | None = None,
) -> list[dict[str, Any]]:
    """Sample up to `count` performance questions (client-safe, no answers)."""
    nids = performance_note_ids(col, section=section)
    rng = random.Random(seed)
    rng.shuffle(nids)
    chosen = nids[:count]
    return [serialize_question(col, nid) for nid in chosen]


def memory_note_ids(
    col: anki.collection.Collection,
    *,
    section: str | None = None,
    topic_id: str | None = None,
) -> list[int]:
    """Note ids for MCAT memory flashcards, optionally filtered by section."""
    terms = [
        f'"note:{schema.NOTETYPE_MEMORY}"',
        f'"tag:{schema.TAG_EXAM}"',
    ]
    if section:
        terms.append(f'"tag:{schema.TAG_SECTION_PREFIX}{section}"')
    if topic_id:
        terms.append(f'"tag:{schema.TAG_TOPIC_PREFIX}{topic_id}"')
    return [int(nid) for nid in col.find_notes(" ".join(terms))]


def serialize_flashcard(
    col: anki.collection.Collection, note_id: int
) -> dict[str, Any]:
    import anki.notes

    note = col.get_note(anki.notes.NoteId(note_id))
    cards = note.cards()
    return {
        "note_id": note_id,
        "card_id": int(cards[0].id) if cards else None,
        "front": note["Front"] if "Front" in note else "",
        "back": note["Back"] if "Back" in note else "",
        "section": note["Section"] if "Section" in note else "",
        "topic_ids": schema.parse_topics(list(note.tags)),
    }


def sample_flashcards(
    col: anki.collection.Collection,
    *,
    section: str | None,
    count: int,
    seed: int | None = None,
) -> list[dict[str, Any]]:
    nids = memory_note_ids(col, section=section)
    rng = random.Random(seed)
    rng.shuffle(nids)
    return [serialize_flashcard(col, nid) for nid in nids[:count]]


def serialize_question(col: anki.collection.Collection, note_id: int) -> dict[str, Any]:
    """Client-safe question payload (no correct answer, no explanation)."""
    import anki.notes

    note = col.get_note(anki.notes.NoteId(note_id))
    choices = []
    for letter, field in _CHOICE_FIELDS:
        text = note[field] if field in note else ""
        if text:
            choices.append({"key": letter, "text": text})
    return {
        "note_id": note_id,
        "question": note["Question"] if "Question" in note else "",
        "choices": choices,
        "section": note["Section"] if "Section" in note else "",
        "topic_ids": schema.parse_topics(list(note.tags)),
        "difficulty": schema.parse_difficulty(list(note.tags)),
        "source_id": note["SourceId"] if "SourceId" in note else "",
    }


def correct_choice(col: anki.collection.Collection, note_id: int) -> str:
    import anki.notes

    note = col.get_note(anki.notes.NoteId(note_id))
    return (note["CorrectChoice"] if "CorrectChoice" in note else "").strip().upper()


def reveal_payload(col: anki.collection.Collection, note_id: int) -> dict[str, Any]:
    """Answer + explanation, returned only after the second pass / all-correct."""
    import anki.notes

    note = col.get_note(anki.notes.NoteId(note_id))
    return {
        "note_id": note_id,
        "correct": correct_choice(col, note_id),
        "explanation": note["Explanation"] if "Explanation" in note else "",
    }
