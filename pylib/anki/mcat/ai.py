# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""AI layer for MCAT Speedrun (OpenAI).

Every AI feature routes through here. Design rules (mirroring the PRD's honesty
requirements):

- Gated: nothing here runs unless the profile has `ai_enabled` (checked by the
  caller via `enabled`). With AI off, the app behaves exactly as the no-AI build.
- Grounded: prompts always carry a NAMED SOURCE (the question's own explanation,
  the passage text, etc.), passed back to the UI as `source` so every AI output
  is traceable.
- Fail-safe: any network/timeout/parse error returns `None` (callers fall back
  to the deterministic non-AI experience). AI never blocks or crashes a session.
- Cheap + fast: responses are cached in the collection config by a hash of the
  model+prompt, so re-opening a review doesn't re-bill the API and works offline.

Pure stdlib (urllib) — no extra dependencies, matching firebase_sync.py.
"""

from __future__ import annotations

import hashlib
import json
import os
import urllib.error
import urllib.request
from pathlib import Path
from typing import TYPE_CHECKING, Any

from anki.mcat import store

if TYPE_CHECKING:
    import anki.collection

_KEY_PATH = Path(__file__).with_name(".openai_key")
_API_URL = "https://api.openai.com/v1/chat/completions"
_MODEL = "gpt-4o-mini"  # fast + cheap; good enough for grading + short coaching
_TIMEOUT = 30


def _api_key() -> str | None:
    """Load the OpenAI key from the env or the gitignored local key file."""
    env = os.environ.get("OPENAI_API_KEY")
    if env:
        return env.strip()
    try:
        return _KEY_PATH.read_text(encoding="utf-8").strip() or None
    except OSError:
        return None


def available() -> bool:
    """True when an API key is configured (independent of the user toggle)."""
    return bool(_api_key())


def enabled(col: anki.collection.Collection) -> bool:
    """True when the user has AI on AND a key is configured."""
    return bool(store.get_profile(col).get("ai_enabled", True)) and available()


# Low-level call + cache
#############################################################################


def _cache_get(col: anki.collection.Collection, key: str) -> Any | None:
    cache = col.get_config(store.KEY_AI_CACHE, None)
    if isinstance(cache, dict):
        return cache.get(key)
    return None


def _cache_put(col: anki.collection.Collection, key: str, value: Any) -> None:
    cache = col.get_config(store.KEY_AI_CACHE, None)
    if not isinstance(cache, dict):
        cache = {}
    cache[key] = value
    # Keep the cache bounded so the collection config doesn't grow forever.
    if len(cache) > 500:
        for old in list(cache)[: len(cache) - 500]:
            cache.pop(old, None)
    col.set_config(store.KEY_AI_CACHE, cache)


def _chat(
    col: anki.collection.Collection,
    *,
    system: str,
    user: str,
    want_json: bool,
    cache: bool = True,
) -> str | None:
    """One chat completion. Returns the assistant text, or None on any failure."""
    api_key = _api_key()
    if not api_key:
        return None

    cache_key = ""
    if cache:
        digest = hashlib.sha256(
            f"{_MODEL}\x1f{system}\x1f{user}".encode("utf-8")
        ).hexdigest()
        cache_key = f"c:{digest}"
        cached = _cache_get(col, cache_key)
        if isinstance(cached, str):
            return cached

    payload: dict[str, Any] = {
        "model": _MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "temperature": 0.3,
        "max_tokens": 700,
    }
    if want_json:
        payload["response_format"] = {"type": "json_object"}

    try:
        req = urllib.request.Request(
            _API_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {api_key}",
            },
        )
        with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        text = data["choices"][0]["message"]["content"]
    except (urllib.error.URLError, KeyError, IndexError, ValueError, OSError):
        return None

    if cache and text:
        _cache_put(col, cache_key, text)
    return text


def _chat_json(
    col: anki.collection.Collection, *, system: str, user: str
) -> dict[str, Any] | None:
    text = _chat(col, system=system, user=user, want_json=True)
    if not text:
        return None
    try:
        parsed = json.loads(text)
        return parsed if isinstance(parsed, dict) else None
    except ValueError:
        return None


# Feature: reasoning feedback on a performance question
#############################################################################


def grade_reasoning(
    col: anki.collection.Collection,
    *,
    question: str,
    choices: list[dict[str, str]],
    student_choice: str,
    correct_choice: str,
    explanation: str,
    student_reasoning: str,
) -> dict[str, Any] | None:
    """Grade a student's free-response reasoning against the question's own
    explanation (the NAMED SOURCE). Returns a dict with a verdict + feedback, or
    None if AI is unavailable (caller falls back to just showing the explanation).
    """
    choice_lines = "\n".join(f"{c['key']}. {c['text']}" for c in choices)
    system = (
        "You are an MCAT tutor giving short, specific feedback on a student's "
        "reasoning. Judge ONLY against the provided official explanation — do not "
        "invent facts. Be encouraging but honest. Respond as JSON with keys: "
        "verdict (one of 'sound','partially_sound','flawed'), feedback (2-3 "
        "sentences addressed to the student), key_point (the single most "
        "important idea they should take away)."
    )
    user = (
        f"QUESTION:\n{question}\n\nCHOICES:\n{choice_lines}\n\n"
        f"STUDENT'S ANSWER: {student_choice or '(none)'}\n"
        f"CORRECT ANSWER: {correct_choice}\n"
        f"OFFICIAL EXPLANATION (your source of truth):\n{explanation}\n\n"
        f"STUDENT'S REASONING:\n{student_reasoning or '(they did not explain)'}"
    )
    out = _chat_json(col, system=system, user=user)
    if not out:
        return None
    return {
        "verdict": str(out.get("verdict", "")),
        "feedback": str(out.get("feedback", "")).strip(),
        "key_point": str(out.get("key_point", "")).strip(),
        "source": "Official answer explanation",
    }


# Feature: personalized study coach
#############################################################################


def coach_recommendation(
    col: anki.collection.Collection, *, scores: dict[str, Any]
) -> dict[str, Any] | None:
    """Read the student's scores (memory/performance/readiness + per-section
    coverage and confidence) and recommend the single best next step. Grounded in
    the computed scores, which are named as the source."""
    # Compact the scores so the prompt is small + cheap.
    sections = {}
    for code, s in scores.get("sections", {}).items():
        sections[code] = {
            "coverage_pct": s.get("coverage_pct"),
            "memory": s["memory"].get("point"),
            "performance": s["performance"].get("point"),
            "readiness": None if s["readiness"].get("abstained") else s["readiness"].get("point"),
        }
    facts = {
        "memory": scores["memory"].get("point"),
        "performance": scores["performance"].get("point"),
        "readiness": None if scores["readiness"].get("abstained") else scores["readiness"].get("point"),
        "sections": sections,
    }
    system = (
        "You are an MCAT study coach. Given the student's measured scores, decide "
        "the single most useful next action. Prefer prerequisite flashcards when "
        "memory is weak or coverage is low; prefer performance practice in a named "
        "section when memory is fine but applied accuracy lags. Respond as JSON "
        "with keys: focus (one of 'memory','performance','coverage','balanced'), "
        "section (a section code 'bb','cp','ps','cars' or ''), headline (<=8 words), "
        "detail (2 sentences, specific and actionable)."
    )
    user = "STUDENT SCORES (your source):\n" + json.dumps(facts, indent=1)
    out = _chat_json(col, system=system, user=user)
    if not out:
        return None
    return {
        "focus": str(out.get("focus", "balanced")),
        "section": str(out.get("section", "")),
        "headline": str(out.get("headline", "")).strip(),
        "detail": str(out.get("detail", "")).strip(),
        "source": "Your measured scores",
    }


# Feature: CARS debate
#############################################################################


def cars_debate_reply(
    col: anki.collection.Collection,
    *,
    passage: str,
    author_claim: str,
    history: list[dict[str, str]],
    student_message: str,
) -> dict[str, Any] | None:
    """Respond in a CARS debate as the author defending their claim. Grounded in
    the passage text (the named source). `history` is [{role, content}]."""
    system = (
        "You are role-playing the AUTHOR of an MCAT CARS passage in a debate with "
        "a student. Defend the passage's argument using ONLY reasoning and evidence "
        "grounded in the passage — never outside facts. Push back on weak points, "
        "concede genuinely strong ones, and keep it to 2-4 sentences. Then, "
        "separately, give a brief coaching note on the quality of the student's "
        "reasoning. Respond as JSON with keys: reply (the author's rebuttal), "
        "critique (1 sentence on the student's reasoning skill), "
        "skill (one CARS skill being exercised)."
    )
    convo = "\n".join(f"{m['role']}: {m['content']}" for m in history[-6:])
    user = (
        f"PASSAGE (your source of truth):\n{passage}\n\n"
        f"AUTHOR'S CENTRAL CLAIM: {author_claim}\n\n"
        f"DEBATE SO FAR:\n{convo or '(start)'}\n\n"
        f"STUDENT'S LATEST ARGUMENT:\n{student_message}"
    )
    # Debate turns are conversational, so don't cache them.
    text = _chat(col, system=system, user=user, want_json=True, cache=False)
    if not text:
        return None
    try:
        out = json.loads(text)
    except ValueError:
        return None
    return {
        "reply": str(out.get("reply", "")).strip(),
        "critique": str(out.get("critique", "")).strip(),
        "skill": str(out.get("skill", "")).strip(),
        "source": "Passage text",
    }
