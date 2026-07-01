# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Data-access layer for MCAT-specific state, stored in the collection config.

Everything here is persisted via `col.get_config`/`col.set_config`, which means
it lives inside the synced collection: it syncs across devices, participates in
undo, and never touches the database schema. Keys are namespaced under `mcat:`.

The records intentionally capture all the fields a future AI layer will need
(reasoning text, source ids, mistake labels, calibration), even though AI is
off today.
"""

from __future__ import annotations

import time
import uuid
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    import anki.collection

# Config keys
#############################################################################

KEY_PROFILE = "mcat:profile"
KEY_PLAN = "mcat:plan"
KEY_ATTEMPTS = "mcat:attempts"
KEY_DEBATES = "mcat:debates"
KEY_STREAK = "mcat:streak"
KEY_SCORES_CACHE = "mcat:scores_cache"
# Dev-only manual score override (set via the dashboard "Set mastery" tool).
KEY_DEV_SCORES = "mcat:dev_scores"
KEY_REMOTE_STUDY = "mcat:remote_study"  # other device's study aggregate (sync)
KEY_MEMORY_REVIEWS = "mcat:memory_reviews"  # this device's memory-review tally
KEY_MCAT_LOG = "mcat:log"  # this device's shared-engine event log (McatState)
KEY_REMOTE_MCAT_LOG = "mcat:remote_log"  # the other device's engine log (synced in)

# Dev backdoor: logging in with these credentials flips the profile into dev
# mode, which exposes a "mark block done" tool on the roadmap for testing the
# flow (scores, streak, progression) without doing the actual work. These are
# local-only and live in the synced collection config.
DEV_EMAIL = "dev@mcat.com"
DEV_PASSWORD = "devaccount"


def is_dev_login(email: str, password: str) -> bool:
    return (
        email.strip().lower() == DEV_EMAIL.strip().lower() and password == DEV_PASSWORD
    )


def _now() -> int:
    return int(time.time())


def _new_id() -> str:
    return uuid.uuid4().hex


# Profile (exam date, available time, onboarding state)
#############################################################################


def get_profile(col: anki.collection.Collection) -> dict[str, Any]:
    profile = col.get_config(KEY_PROFILE, None)
    defaults: dict[str, Any] = {
        "name": None,
        "email": None,
        "password": None,  # local-only; never returned to the client
        "auth_provider": "password",  # "password" | "google"
        "exam_date": None,  # ISO date string
        "daily_minutes": 120,  # 2 hours/day recommended baseline
        "onboarding_done": False,
        "diagnostic_done": False,
        "diagnostic_kind": None,  # quick | standard | best_estimate
        "logged_in": True,  # local session flag; logout sets this false
        "is_dev": False,  # dev-mode tools (roadmap "mark done")
    }
    if not isinstance(profile, dict):
        return defaults
    # Backfill any keys added in newer versions.
    for key, value in defaults.items():
        profile.setdefault(key, value)
    return profile


def set_profile(col: anki.collection.Collection, profile: dict[str, Any]) -> None:
    col.set_config(KEY_PROFILE, profile)


def update_profile(col: anki.collection.Collection, **changes: Any) -> dict[str, Any]:
    profile = get_profile(col)
    profile.update(changes)
    set_profile(col, profile)
    return profile


# Attempts (performance practice + diagnostic + mini-MCAT)
#############################################################################


def new_attempt(
    *,
    note_id: int | None,
    card_id: int | None,
    section: str,
    topic_ids: list[str],
    difficulty: int,
    source_id: str,
    mode: str,
    phase: str,
    first_choice: str,
    first_correct: bool,
    confidence: str,
    first_time_ms: int,
    batch_id: str | None = None,
) -> dict[str, Any]:
    """Build a first-pass attempt record. Second-pass fields filled in later."""
    return {
        "id": _new_id(),
        "ts": _now(),
        "note_id": note_id,
        "card_id": card_id,
        "section": section,
        "topic_ids": list(topic_ids),
        "difficulty": difficulty,
        "source_id": source_id,
        "mode": mode,
        "phase": phase,
        "batch_id": batch_id,
        # first pass
        "first_choice": first_choice,
        "first_correct": first_correct,
        "confidence": confidence,
        "first_time_ms": first_time_ms,
        # second pass (delayed batch feedback -> revise)
        "second_choice": None,
        "second_correct": None,
        "changed_answer": None,
        "reasoning_text": "",
        "second_pass_label": None,
        # diagnosis (AI-ready)
        "mistake_label": None,
    }


def apply_second_pass(
    attempt: dict[str, Any],
    *,
    second_choice: str,
    second_correct: bool,
    reasoning_text: str,
) -> dict[str, Any]:
    """Fill in the second-pass fields and derive the non-AI label."""
    changed = second_choice != attempt.get("first_choice")
    attempt["second_choice"] = second_choice
    attempt["second_correct"] = second_correct
    attempt["changed_answer"] = changed
    attempt["reasoning_text"] = reasoning_text
    attempt["second_pass_label"] = _second_pass_label(
        first_correct=bool(attempt.get("first_correct")),
        second_correct=second_correct,
        changed=changed,
        confidence=str(attempt.get("confidence", "")),
    )
    return attempt


def _second_pass_label(
    *, first_correct: bool, second_correct: bool, changed: bool, confidence: str
) -> str:
    if second_correct and not first_correct:
        return "correct_after_retry"
    if not second_correct:
        return "incorrect_after_retry"
    if changed:
        return "changed_answer"
    if confidence in ("certain", "leaning"):
        return "stayed_confident"
    return "stayed_uncertain"


def get_attempts(col: anki.collection.Collection) -> list[dict[str, Any]]:
    attempts = col.get_config(KEY_ATTEMPTS, None)
    if not isinstance(attempts, list):
        return []
    return attempts


def save_attempts(
    col: anki.collection.Collection, attempts: list[dict[str, Any]]
) -> None:
    col.set_config(KEY_ATTEMPTS, attempts)


def add_attempt(
    col: anki.collection.Collection, attempt: dict[str, Any]
) -> dict[str, Any]:
    attempts = get_attempts(col)
    attempts.append(attempt)
    save_attempts(col, attempts)
    return attempt


def update_attempt(col: anki.collection.Collection, attempt: dict[str, Any]) -> None:
    attempts = get_attempts(col)
    for idx, existing in enumerate(attempts):
        if existing.get("id") == attempt.get("id"):
            attempts[idx] = attempt
            save_attempts(col, attempts)
            return
    # not found -> append
    add_attempt(col, attempt)


def attempts_for_section(
    col: anki.collection.Collection, section: str
) -> list[dict[str, Any]]:
    return [a for a in get_attempts(col) if a.get("section") == section]


# CARS debate responses
#############################################################################


def add_debate(col: anki.collection.Collection, debate: dict[str, Any]) -> None:
    debates = col.get_config(KEY_DEBATES, None)
    if not isinstance(debates, list):
        debates = []
    debate.setdefault("id", _new_id())
    debate.setdefault("ts", _now())
    debates.append(debate)
    col.set_config(KEY_DEBATES, debates)


def get_debates(col: anki.collection.Collection) -> list[dict[str, Any]]:
    debates = col.get_config(KEY_DEBATES, None)
    if not isinstance(debates, list):
        return []
    return debates


# Daily plan / roadmap + streak
#############################################################################


def get_plan(col: anki.collection.Collection) -> dict[str, Any] | None:
    plan = col.get_config(KEY_PLAN, None)
    if not isinstance(plan, dict):
        return None
    return plan


def set_plan(col: anki.collection.Collection, plan: dict[str, Any]) -> None:
    col.set_config(KEY_PLAN, plan)


def get_streak(col: anki.collection.Collection) -> dict[str, Any]:
    streak = col.get_config(KEY_STREAK, None)
    if not isinstance(streak, dict):
        streak = {"count": 0, "last_completed_date": None}
    return streak


def set_streak(col: anki.collection.Collection, streak: dict[str, Any]) -> None:
    col.set_config(KEY_STREAK, streak)


# Dev score override
#############################################################################


def get_dev_scores(col: anki.collection.Collection) -> dict[str, Any] | None:
    override = col.get_config(KEY_DEV_SCORES, None)
    if not isinstance(override, dict):
        return None
    return override


def set_dev_scores(col: anki.collection.Collection, override: dict[str, Any]) -> None:
    col.set_config(KEY_DEV_SCORES, override)


def clear_dev_scores(col: anki.collection.Collection) -> None:
    col.remove_config(KEY_DEV_SCORES)


def get_remote_study(col: anki.collection.Collection) -> dict[str, Any]:
    """Per-section study aggregate contributed by the OTHER device (e.g. iOS),
    pulled from Firestore so the desktop's scores reflect combined study."""
    data = col.get_config(KEY_REMOTE_STUDY, None)
    return data if isinstance(data, dict) else {}


def set_remote_study(col: anki.collection.Collection, data: dict[str, Any]) -> None:
    col.set_config(KEY_REMOTE_STUDY, data)


# Shared-engine event log (mcat_core McatState)
#############################################################################


def mcat_card_key(kind: str, section: str, text: str) -> str:
    """Stable content key shared with the engine + iOS (SHA-256, first 16 hex).
    `kind` is "m" for memory cards, "p" for performance questions."""
    import hashlib

    joined = f"{kind}|{section}|{text}"
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()[:16]


def _empty_log() -> dict[str, Any]:
    return {"reviews": [], "attempts": []}


def get_mcat_log(col: anki.collection.Collection) -> dict[str, Any]:
    """This device's engine event log (memory reviews + performance attempts)."""
    data = col.get_config(KEY_MCAT_LOG, None)
    if not isinstance(data, dict):
        return _empty_log()
    data.setdefault("reviews", [])
    data.setdefault("attempts", [])
    return data


def set_mcat_log(col: anki.collection.Collection, log: dict[str, Any]) -> None:
    col.set_config(KEY_MCAT_LOG, log)


def get_remote_mcat_log(col: anki.collection.Collection) -> dict[str, Any]:
    data = col.get_config(KEY_REMOTE_MCAT_LOG, None)
    if not isinstance(data, dict):
        return _empty_log()
    return data


def set_remote_mcat_log(col: anki.collection.Collection, log: dict[str, Any]) -> None:
    col.set_config(KEY_REMOTE_MCAT_LOG, log)


def append_review_event(
    col: anki.collection.Collection, *, card_key: str, section: str, rating: int
) -> None:
    if not card_key or not section:
        return
    log = get_mcat_log(col)
    log["reviews"].append(
        {
            "id": uuid.uuid4().hex,
            "card_key": card_key,
            "section": section,
            "ts": int(time.time()),
            "rating": int(rating),
        }
    )
    set_mcat_log(col, log)


def append_attempt_events(
    col: anki.collection.Collection, attempts: list[dict[str, Any]]
) -> None:
    """Append performance attempt events. Each item: {section, question_key,
    first_correct, batch_id}. An id + ts are filled in here."""
    if not attempts:
        return
    log = get_mcat_log(col)
    ts = int(time.time())
    for a in attempts:
        log["attempts"].append(
            {
                "id": uuid.uuid4().hex,
                "section": a.get("section", ""),
                "question_key": a.get("question_key", ""),
                "ts": ts,
                "first_correct": bool(a.get("first_correct")),
                "batch_id": a.get("batch_id", ""),
            }
        )
    set_mcat_log(col, log)


def get_memory_reviews(col: anki.collection.Collection) -> dict[str, Any]:
    """This device's memory-review tally per section: {reviews, reviewsCorrect}.
    Drives the Memory score with the SAME recall metric the iOS app uses, so the
    two apps produce identical numbers (FSRS still schedules the cards)."""
    data = col.get_config(KEY_MEMORY_REVIEWS, None)
    return data if isinstance(data, dict) else {}


def record_memory_review(
    col: anki.collection.Collection, section: str, good: bool
) -> None:
    if not section:
        return
    data = get_memory_reviews(col)
    entry = data.get(section) or {"reviews": 0, "reviewsCorrect": 0}
    entry["reviews"] = int(entry.get("reviews", 0)) + 1
    if good:
        entry["reviewsCorrect"] = int(entry.get("reviewsCorrect", 0)) + 1
    data[section] = entry
    col.set_config(KEY_MEMORY_REVIEWS, data)
