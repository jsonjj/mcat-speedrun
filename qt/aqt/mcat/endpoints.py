# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""JSON HTTP handlers for the MCAT Speedrun web pages.

Each function reads the JSON POST body from `flask.request` and returns JSON
bytes. They are registered into aqt.mediasrv's `post_handler_list`, so the
frontend reaches them at `/_anki/<camelCaseName>`. Correctness for performance
questions is always computed here on the backend, so delayed batch feedback and
second-pass reasoning stay honest (the client never receives answers early).
"""

from __future__ import annotations

import json
import random
import time
import uuid
from typing import Any

import flask

import aqt
from anki.mcat import (
    content,
    firebase_sync,
    planner,
    questions,
    schema,
    scoring,
    store,
)


def _col() -> Any:
    return aqt.mw.col


def _body() -> dict[str, Any]:
    raw = flask.request.data
    if not raw:
        return {}
    return json.loads(raw)


def _json(payload: Any) -> bytes:
    return json.dumps(payload).encode("utf-8")


def _public(profile: dict[str, Any]) -> dict[str, Any]:
    """Profile safe to send to the client (no password)."""
    safe = dict(profile)
    safe.pop("password", None)
    return safe


# Dashboard / setup
#############################################################################


def mcat_dashboard() -> bytes:
    col = _col()
    firebase_sync.pull(col)  # best-effort: reflect changes made on other devices
    has_content = bool(questions.performance_note_ids(col))
    if has_content:
        content.ensure_current(col)  # swap in updated flashcards if the pack changed
    payload = {
        "has_content": has_content,
        "profile": _public(store.get_profile(col)),
        "streak": store.get_streak(col),
        "scores": scoring.compute_scores(col) if has_content else None,
    }
    return _json(payload)


def mcat_bootstrap() -> bytes:
    """Ensure notetypes exist and install MCAT content if the deck is empty."""
    col = _col()
    schema.ensure_mcat_notetypes(col)
    if questions.performance_note_ids(col):
        # Content already installed — refresh flashcards if the pack changed.
        return _json(
            {
                "loaded": False,
                "reason": "content already present",
                "content_update": content.ensure_current(col),
            }
        )
    counts = content.load_default_content(col)
    # The main content pack carries multiple-choice CARS; the debate mode needs
    # dedicated debate passages, so load those if none exist yet.
    if not col.find_notes(f'"note:{schema.NOTETYPE_CARS}"'):
        debate_counts = content.load_cars_debates(col)
        counts["cars"] = counts.get("cars", 0) + debate_counts.get("cars", 0)
    # A fresh install already has the current flashcards.
    col.set_config(content.VERSION_KEY, content.CONTENT_VERSION)
    return _json({"loaded": True, "counts": counts})


def mcat_get_profile() -> bytes:
    return _json(
        {
            "profile": _public(store.get_profile(_col())),
            "streak": store.get_streak(_col()),
        }
    )


def mcat_account() -> bytes:
    col = _col()
    firebase_sync.pull(col)  # best-effort: reflect changes made on other devices
    has_content = bool(questions.performance_note_ids(col))
    return _json(
        {
            "profile": _public(store.get_profile(col)),
            "streak": store.get_streak(col),
            "scores": scoring.compute_scores(col) if has_content else None,
        }
    )


def mcat_save_profile() -> bytes:
    body = _body()
    changes: dict[str, Any] = {}
    allowed = (
        "name",
        "email",
        "password",
        "auth_provider",
        "exam_date",
        "daily_minutes",
        "onboarding_done",
        "diagnostic_done",
        "diagnostic_kind",
        "logged_in",
    )
    for key in allowed:
        if key in body:
            changes[key] = body[key]
    col = _col()
    profile = store.update_profile(col, **changes)
    # Keep the cloud in sync (best-effort); logging out ends the session.
    if changes.get("logged_in") is False:
        firebase_sync.sign_out(col)
    else:
        firebase_sync.push(col)
    return _json({"profile": _public(profile)})


def mcat_signup() -> bytes:
    """Create a real Firebase account (email/password) so it syncs across
    devices, then seed the cloud doc from the local profile."""
    body = _body()
    col = _col()
    email = str(body.get("email", "")).strip()
    password = str(body.get("password", ""))
    name = str(body.get("name", "")).strip()

    def _finish() -> bytes:
        profile = store.update_profile(
            col,
            name=name or None,
            email=email or None,
            auth_provider="password",
            exam_date=body.get("exam_date"),
            daily_minutes=int(body.get("daily_minutes", 120)),
            onboarding_done=True,
            logged_in=True,
            is_dev=False,
        )
        return _json({"ok": True, "profile": _public(profile)})

    if not firebase_sync.available():
        return _finish()  # offline / unconfigured: local-only account
    _session, err = firebase_sync.sign_up(col, email, password)
    if err:
        return _json({"ok": False, "error": err})
    result = _finish()
    firebase_sync.push(col)
    return result


def mcat_login() -> bytes:
    """Sign in via Firebase (email/password), then pull the account's cloud
    state. Falls back to the local account when Firebase isn't reachable, and
    keeps the dev backdoor + Google stand-in."""
    body = _body()
    col = _col()
    email = str(body.get("email", "")).strip()
    password = str(body.get("password", ""))

    # Google sign-in: a local, password-less account. (No real OAuth here — this
    # is the on-device stand-in for "Continue with Google".)
    if body.get("provider") == "google":
        profile = store.get_profile(col)
        if not profile.get("onboarding_done"):
            return _json(
                {"ok": False, "error": "No Google account here yet — sign up first."}
            )
        profile = store.update_profile(col, logged_in=True, is_dev=False)
        return _json({"ok": True, "profile": _public(profile)})

    # Dev backdoor: enables the roadmap "mark done" testing tools.
    if store.is_dev_login(email, password):
        profile = store.update_profile(col, logged_in=True, is_dev=True)
        return _json({"ok": True, "profile": _public(profile)})

    # Real account: authenticate against Firebase, then pull cloud state.
    if firebase_sync.available():
        _session, err = firebase_sync.sign_in(col, email, password)
        if err:
            return _json({"ok": False, "error": err})
        store.update_profile(col, logged_in=True, is_dev=False, email=email)
        firebase_sync.pull(col)
        return _json({"ok": True, "profile": _public(store.get_profile(col))})

    # Fallback: local account (offline / Firebase unconfigured).
    profile = store.get_profile(col)
    if not profile.get("onboarding_done"):
        return _json(
            {"ok": False, "error": "No account on this device yet — create one first."}
        )
    stored_email = (profile.get("email") or "").strip().lower()
    if stored_email and email.lower() != stored_email:
        return _json(
            {"ok": False, "error": "That email doesn't match this device's account."}
        )
    stored_pw = profile.get("password") or ""
    if stored_pw and password != stored_pw:
        return _json({"ok": False, "error": "Incorrect password."})
    profile = store.update_profile(col, logged_in=True, is_dev=False)
    return _json({"ok": True, "profile": _public(profile)})


def mcat_sync_pull() -> bytes:
    """Pull the account's cloud state (used on page loads / manual sync)."""
    col = _col()
    err = firebase_sync.pull(col)
    return _json(
        {
            "ok": not err,
            "error": err or None,
            "profile": _public(store.get_profile(col)),
        }
    )


# Questions / Mini-MCAT / diagnostic
#############################################################################


def mcat_questions() -> bytes:
    body = _body()
    col = _col()
    section = body.get("section")
    count = int(body.get("count", 5))
    qs = questions.sample_questions(col, section=section, count=count)
    return _json({"batch_id": uuid.uuid4().hex, "questions": qs})


def mcat_mini_questions() -> bytes:
    """A Mini-MCAT batch: sample per section and concatenate."""
    body = _body()
    col = _col()
    total = int(body.get("count", 20))
    per_section = max(1, total // len(schema.SECTIONS))
    qs: list[dict[str, Any]] = []
    for section in schema.SECTIONS:
        qs.extend(questions.sample_questions(col, section=section, count=per_section))
    return _json(
        {"batch_id": uuid.uuid4().hex, "phase": schema.PHASE_DAILY, "questions": qs}
    )


def mcat_flashcards() -> bytes:
    """Memory cards to review, DUE ones first (spaced repetition). Due-ness comes
    from the shared engine's FSRS state over the merged log, so a card reviewed on
    the phone won't resurface here until it's due (and vice-versa)."""
    import anki.notes

    body = _body()
    col = _col()
    section = body.get("section")
    count = int(body.get("count", 15))

    nids = questions.memory_note_ids(col, section=section)
    key_to_nid: dict[str, int] = {}
    all_keys: list[str] = []
    for nid in nids:
        note = col.get_note(anki.notes.NoteId(nid))
        sec = note["Section"] if "Section" in note else ""
        front = note["Front"] if "Front" in note else ""
        key = store.mcat_card_key("m", sec, front)
        key_to_nid[key] = nid
        all_keys.append(key)

    combined = col._backend.mcat_merge(
        state_json=json.dumps(store.get_mcat_log(col)),
        other_json=json.dumps(store.get_remote_mcat_log(col)),
    )
    due_keys = set(
        json.loads(
            col._backend.mcat_due_cards(
                state_json=combined,
                all_keys_json=json.dumps(all_keys),
                now_ts=int(time.time()),
                retention=0.9,
            )
        )
    )
    due_nids = [key_to_nid[k] for k in all_keys if k in due_keys]
    rest_nids = [key_to_nid[k] for k in all_keys if k not in due_keys]
    random.shuffle(due_nids)
    random.shuffle(rest_nids)
    chosen = (due_nids + rest_nids)[:count]
    cards = [questions.serialize_flashcard(col, nid) for nid in chosen]
    return _json({"cards": cards})


def mcat_grade_card() -> bytes:
    """Grade a memory card with an FSRS rating so it schedules + feeds Memory."""
    import anki.cards
    from anki.scheduler.v3 import CardAnswer

    body = _body()
    col = _col()
    card_id = int(body.get("card_id", 0) or 0)
    ratings = {
        "again": CardAnswer.AGAIN,
        "hard": CardAnswer.HARD,
        "good": CardAnswer.GOOD,
        "easy": CardAnswer.EASY,
    }
    rating = ratings.get(str(body.get("rating", "good")).lower(), CardAnswer.GOOD)
    ok = True
    error = ""
    if card_id:
        try:
            card = col.get_card(anki.cards.CardId(card_id))
            card.start_timer()
            states = col._backend.get_scheduling_states(card.id)
            answer = col.sched.build_answer(card=card, states=states, rating=rating)
            col.sched.answer_card(answer)
            # Record the review into the shared-engine event log (card key +
            # rating), so per-card FSRS state + the Memory score sync per-card.
            note = card.note()
            section = note["Section"] if "Section" in note else ""
            front = note["Front"] if "Front" in note else ""
            store.append_review_event(
                col,
                card_key=store.mcat_card_key("m", section, front),
                section=section,
                rating=int(rating),
            )
        except Exception as err:
            ok = False
            error = str(err)
    if ok:
        firebase_sync.push(col)  # sync the review promptly (best-effort)
    return _json({"ok": ok, "error": error})


def mcat_diagnostic_questions() -> bytes:
    body = _body()
    col = _col()
    kind = body.get("kind", "standard")
    spec = planner.diagnostic_spec(kind)
    qs: list[dict[str, Any]] = []
    for section in schema.SECTIONS:
        qs.extend(
            questions.sample_questions(
                col, section=section, count=int(spec["per_section"])
            )
        )
    return _json(
        {
            "batch_id": uuid.uuid4().hex,
            "phase": schema.PHASE_DIAGNOSTIC,
            "kind": kind,
            "spec": spec,
            "questions": qs,
        }
    )


def mcat_submit_first() -> bytes:
    """Record first-pass answers; return delayed batch feedback (no reveal)."""
    body = _body()
    col = _col()
    batch_id = body.get("batch_id") or uuid.uuid4().hex
    phase = body.get("phase", schema.PHASE_DAILY)
    answers = body.get("answers", [])

    wrong = 0
    results: list[dict[str, Any]] = []
    log_attempts: list[dict[str, Any]] = []
    for ans in answers:
        note_id = int(ans["note_id"])
        choice = str(ans.get("choice", "")).strip().upper()
        meta = questions.serialize_question(col, note_id)
        correct_key = questions.correct_choice(col, note_id)
        first_correct = bool(choice) and choice == correct_key
        if not first_correct:
            wrong += 1
        attempt = store.new_attempt(
            note_id=note_id,
            card_id=None,
            section=meta["section"],
            topic_ids=meta["topic_ids"],
            difficulty=meta["difficulty"],
            source_id=meta["source_id"],
            mode=schema.MODE_PERFORMANCE,
            phase=phase,
            first_choice=choice,
            first_correct=first_correct,
            confidence=str(ans.get("confidence", schema.CONFIDENCE_GUESSING)),
            first_time_ms=int(ans.get("time_ms", 0)),
            batch_id=batch_id,
        )
        store.add_attempt(col, attempt)
        log_attempts.append(
            {
                "section": meta["section"],
                "question_key": store.mcat_card_key(
                    "p", meta["section"], meta["question"]
                ),
                "first_correct": first_correct,
                "batch_id": batch_id,
            }
        )
        results.append({"note_id": note_id, "first_correct": first_correct})
    # Mirror the attempts into the shared-engine log (for scoring + sync).
    store.append_attempt_events(col, log_attempts)
    firebase_sync.push(col)  # sync this batch's attempts promptly (best-effort)

    total = len(answers)
    if wrong == 0:
        return _json(
            {
                "reveal": True,
                "batch_id": batch_id,
                "wrong_count": 0,
                "total": total,
                "results": [
                    _reveal(col, r["note_id"], r["first_correct"]) for r in results
                ],
            }
        )
    message = (
        f"You got {wrong} questions wrong. You have one more opportunity before the "
        "correct answers are revealed. This time, explain your reasoning for your "
        "final decisions."
    )
    return _json(
        {
            "reveal": False,
            "batch_id": batch_id,
            "wrong_count": wrong,
            "total": total,
            "message": message,
        }
    )


def mcat_submit_second() -> bytes:
    """Record second-pass revisions + reasoning, then reveal everything."""
    body = _body()
    col = _col()
    batch_id = body.get("batch_id")
    answers = body.get("answers", [])

    attempts = store.get_attempts(col)
    by_note = {
        a["note_id"]: a
        for a in attempts
        if a.get("batch_id") == batch_id and a.get("note_id") is not None
    }

    results: list[dict[str, Any]] = []
    for ans in answers:
        note_id = int(ans["note_id"])
        choice = str(ans.get("choice", "")).strip().upper()
        reasoning = str(ans.get("reasoning", ""))
        correct_key = questions.correct_choice(col, note_id)
        second_correct = bool(choice) and choice == correct_key
        attempt = by_note.get(note_id)
        if attempt is not None:
            store.apply_second_pass(
                attempt,
                second_choice=choice,
                second_correct=second_correct,
                reasoning_text=reasoning,
            )
            store.update_attempt(col, attempt)
        results.append(
            {
                **_reveal(col, note_id, bool(attempt and attempt.get("first_correct"))),
                "second_correct": second_correct,
                "label": attempt.get("second_pass_label") if attempt else None,
            }
        )
    return _json({"reveal": True, "batch_id": batch_id, "results": results})


def mcat_complete_diagnostic() -> bytes:
    body = _body()
    col = _col()
    kind = body.get("kind", "standard")
    profile = store.update_profile(
        col, diagnostic_done=True, diagnostic_kind=kind, onboarding_done=True
    )
    firebase_sync.push(col)  # sync diagnostic result + seeded attempts
    return _json({"profile": profile})


def _reveal(col: Any, note_id: int, first_correct: bool) -> dict[str, Any]:
    payload = questions.reveal_payload(col, note_id)
    payload["first_correct"] = first_correct
    return payload


# Roadmap / streak
#############################################################################


def _roadmap_payload(col: Any, plan: dict[str, Any]) -> dict[str, Any]:
    return {
        "plan": plan,
        "streak": store.get_streak(col),
        "free_practice_unlocked": planner.required_complete(plan),
        "is_dev": bool(store.get_profile(col).get("is_dev")),
    }


def mcat_roadmap() -> bytes:
    col = _col()
    firebase_sync.pull(col)  # best-effort: reflect changes made on other devices
    return _json(_roadmap_payload(col, planner.get_or_build_plan(col)))


def mcat_rebuild_roadmap() -> bytes:
    col = _col()
    plan = planner.build_daily_plan(col)
    firebase_sync.push(col)  # propagate the fresh (empty) roadmap progress
    return _json(_roadmap_payload(col, plan))


def mcat_complete_block() -> bytes:
    body = _body()
    col = _col()
    plan = planner.complete_block(col, str(body.get("block_id", "")))
    firebase_sync.push(col)  # sync roadmap progress + any streak change
    return _json(_roadmap_payload(col, plan))


# Dev tools (only usable from a dev account)
#############################################################################


def _find_block(col: Any, block_id: str) -> dict[str, Any] | None:
    plan = planner.get_or_build_plan(col)
    return next((b for b in plan["blocks"] if b.get("id") == block_id), None)


def _dev_synth_perf(col: Any, *, section: str | None, count: int, correct: int) -> None:
    """Record synthetic performance attempts so scores move without real work."""
    sections = [section] if section else list(schema.SECTIONS)
    batch_id = uuid.uuid4().hex
    made = 0
    log_attempts: list[dict[str, Any]] = []
    for i in range(count):
        sec = sections[i % len(sections)]
        pool = questions.performance_note_ids(col, section=sec)
        note_id: int | None = pool[i % len(pool)] if pool else None
        question_text = f"dev-{sec}-{i}"
        if note_id is not None:
            meta = questions.serialize_question(col, note_id)
            topic_ids = meta["topic_ids"]
            difficulty = meta["difficulty"]
            source_id = meta["source_id"]
            question_text = meta["question"]
        else:
            topic_ids, difficulty, source_id = [], 2, "dev"
        first_correct = made < correct
        attempt = store.new_attempt(
            note_id=note_id,
            card_id=None,
            section=sec,
            topic_ids=topic_ids,
            difficulty=difficulty,
            source_id=source_id,
            mode=schema.MODE_PERFORMANCE,
            phase=schema.PHASE_DAILY,
            first_choice="?",
            first_correct=first_correct,
            confidence=schema.CONFIDENCE_GUESSING,
            first_time_ms=0,
            batch_id=batch_id,
        )
        store.add_attempt(col, attempt)
        log_attempts.append(
            {
                "section": sec,
                "question_key": store.mcat_card_key("p", sec, question_text),
                "first_correct": first_correct,
                "batch_id": batch_id,
            }
        )
        made += 1
    store.append_attempt_events(col, log_attempts)


def _dev_grade_memory(
    col: Any, *, section: str | None, count: int, correct: int
) -> None:
    """Actually review `count` memory cards (correct -> Good, else -> Again) so
    the Memory score moves. Operates directly by card id (bypasses the queue)."""
    import anki.notes
    from anki.scheduler.v3 import CardAnswer

    nids = questions.memory_note_ids(col, section=section)
    graded = 0
    for nid in nids:
        if graded >= count:
            break
        note = col.get_note(anki.notes.NoteId(nid))
        for card in note.cards():
            if graded >= count:
                break
            rating = CardAnswer.GOOD if graded < correct else CardAnswer.AGAIN
            card.start_timer()
            states = col._backend.get_scheduling_states(card.id)
            answer = col.sched.build_answer(card=card, states=states, rating=rating)
            col.sched.answer_card(answer)
            sec = note["Section"] if "Section" in note else (section or "")
            front = note["Front"] if "Front" in note else ""
            store.append_review_event(
                col,
                card_key=store.mcat_card_key("m", sec, front),
                section=sec,
                rating=int(rating),
            )
            graded += 1


def mcat_dev_complete_block() -> bytes:
    """Dev-only: record a made-up score for a block, then mark it complete.

    Completion happens regardless of whether the score synthesis succeeds, so the
    block always finishes and the next one unlocks.
    """
    col = _col()
    if not store.get_profile(col).get("is_dev"):
        return _json({"ok": False, "error": "Dev mode only."})
    body = _body()
    block_id = str(body.get("block_id", ""))
    total = max(0, int(body.get("total", 0)))
    correct = max(0, min(total, int(body.get("correct", 0))))

    block = _find_block(col, block_id)
    if block is not None and total > 0:
        try:
            kind = block.get("kind")
            mode = block.get("mode")
            section = block.get("section")
            if kind == "memory" or mode == schema.MODE_MEMORY:
                _dev_grade_memory(col, section=section, count=total, correct=correct)
            elif kind == "cars" or mode == schema.MODE_DEBATE:
                pass  # debate has no numeric score; just complete it
            else:
                _dev_synth_perf(col, section=section, count=total, correct=correct)
        except Exception:
            # Never let score synthesis block the actual completion/advance.
            pass

    plan = planner.complete_block(col, block_id)
    firebase_sync.push(col)  # sync roadmap progress + any streak change
    return _json(_roadmap_payload(col, plan))


def mcat_dev_reset_roadmap() -> bytes:
    """Dev-only: rebuild today's plan from scratch (all blocks incomplete)."""
    col = _col()
    if not store.get_profile(col).get("is_dev"):
        return _json({"ok": False, "error": "Dev mode only."})
    plan = planner.build_daily_plan(col)
    firebase_sync.push(col)  # propagate the reset roadmap progress
    return _json(_roadmap_payload(col, plan))


def mcat_dev_set_scores() -> bytes:
    """Dev-only: pin memory/performance/section scores (readiness = section sum)."""
    col = _col()
    if not store.get_profile(col).get("is_dev"):
        return _json({"ok": False, "error": "Dev mode only."})
    body = _body()
    raw_sections = body.get("sections", {}) or {}
    sections = {
        code: float(raw_sections.get(code, 125) or 125) for code in schema.SECTIONS
    }
    override = {
        "memory_pct": float(body.get("memory_pct", 0) or 0),
        "performance_pct": float(body.get("performance_pct", 0) or 0),
        "sections": sections,
    }
    store.set_dev_scores(col, override)
    return _json({"ok": True, "scores": scoring.compute_scores(col)})


def mcat_dev_clear_scores() -> bytes:
    """Dev-only: remove the manual score override (back to computed scores)."""
    col = _col()
    if not store.get_profile(col).get("is_dev"):
        return _json({"ok": False, "error": "Dev mode only."})
    store.clear_dev_scores(col)
    has_content = bool(questions.performance_note_ids(col))
    return _json(
        {"ok": True, "scores": scoring.compute_scores(col) if has_content else None}
    )


# CARS debate
#############################################################################

# Self-assessment rubric for the Author Duel (non-AI: the student rates their
# own reasoning against these, and unchecked items are logged as miss types).
_CARS_RUBRIC = [
    "I restated the author's main claim in my own words",
    "I stayed inside the passage's evidence (no outside facts)",
    "I argued both sides, not just my own opinion",
    "I judged the new condition by the argument's logic",
]


def mcat_cars() -> bytes:
    import random

    import anki.notes

    col = _col()
    nids = [int(n) for n in col.find_notes(f'"note:{schema.NOTETYPE_CARS}"')]
    if not nids:
        return _json({"passage": None})
    nid = random.choice(nids)
    note = col.get_note(anki.notes.NoteId(nid))
    prompts = note["DebatePrompts"] if "DebatePrompts" in note else "[]"
    try:
        prompts_list = json.loads(prompts)
    except json.JSONDecodeError:
        prompts_list = []
    passage_text = note["Passage"] if "Passage" in note else ""
    enrich = content.cars_enrichment(passage_text)
    return _json(
        {
            "passage": {
                "note_id": nid,
                "passage": passage_text,
                "author_claim": note["AuthorClaim"] if "AuthorClaim" in note else "",
                "prompts": prompts_list,
                "skill_type": note["SkillType"] if "SkillType" in note else "",
                "strong_rebuttal": enrich.get("strong_rebuttal", ""),
                "strong_defense": enrich.get("strong_defense", ""),
                "prompt_skills": enrich.get("prompt_skills", []),
            },
            "rubric": _CARS_RUBRIC,
        }
    )


def mcat_submit_cars() -> bytes:
    body = _body()
    col = _col()
    store.add_debate(
        col,
        {
            "note_id": body.get("note_id"),
            "responses": body.get("responses", {}),
            "verdict": body.get("verdict"),
            "miss_types": body.get("miss_types", []),
        },
    )
    return _json({"saved": True})


# Registry
#############################################################################

# Exposed to aqt.mediasrv; names are camel-cased for the URL.
MCAT_POST_HANDLERS = [
    mcat_dashboard,
    mcat_bootstrap,
    mcat_get_profile,
    mcat_account,
    mcat_save_profile,
    mcat_login,
    mcat_signup,
    mcat_sync_pull,
    mcat_questions,
    mcat_mini_questions,
    mcat_flashcards,
    mcat_grade_card,
    mcat_diagnostic_questions,
    mcat_submit_first,
    mcat_submit_second,
    mcat_complete_diagnostic,
    mcat_roadmap,
    mcat_rebuild_roadmap,
    mcat_complete_block,
    mcat_dev_complete_block,
    mcat_dev_reset_roadmap,
    mcat_dev_set_scores,
    mcat_dev_clear_scores,
    mcat_cars,
    mcat_submit_cars,
]
