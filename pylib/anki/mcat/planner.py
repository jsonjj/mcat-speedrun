# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Daily roadmap planning, diagnostic specs and streak rules.

The roadmap turns an exam date + available minutes into ordered, bite-sized
blocks (5-20 min each). Required blocks must be completed in order for streak
credit. Adaptive focus picks a weak primary section and a smaller secondary
section using the transparent scores (which are powered by the Rust Mastery
Query). No block is longer than ~20 minutes.
"""

from __future__ import annotations

import datetime
import uuid
from typing import TYPE_CHECKING, Any

from anki.mcat import schema, store

if TYPE_CHECKING:
    import anki.collection

MAX_BLOCK_MINUTES = 20
DEFAULT_DAILY_MINUTES = 120  # 2 hours recommended
MIN_DAILY_MINUTES = 30
_MAX_BLOCKS = 16

DIAGNOSTIC_SPECS: dict[str, dict[str, Any]] = {
    "quick": {
        "per_section": 3,
        "total": 12,
        "minutes": "15-20 min",
        "label": "Quick Diagnostic",
    },
    "standard": {
        "per_section": 5,
        "total": 20,
        "minutes": "~30 min",
        "label": "Standard Diagnostic",
    },
    "best_estimate": {
        "per_section": 10,
        "total": 40,
        "minutes": "~60 min",
        "label": "Best-Estimate Diagnostic",
    },
}


def diagnostic_spec(kind: str) -> dict[str, Any]:
    return DIAGNOSTIC_SPECS.get(kind, DIAGNOSTIC_SPECS["standard"])


def full_length_guidance(days_left: int | None) -> dict[str, Any]:
    """Exam-date-aware full-length cadence (PRD: early/middle/final phases)."""
    if days_left is None:
        return {
            "phase": "unscheduled",
            "cadence": "Set an exam date to schedule full-lengths.",
            "recommendation": "Add your exam date on the roadmap.",
        }
    if days_left <= 14:
        return {
            "phase": "final",
            "cadence": "Prioritise full-lengths, review, timing and endurance.",
            "recommendation": "Take a full-length, then a recovery + review day. Flashcards become short maintenance.",
        }
    if days_left <= 60:
        return {
            "phase": "middle",
            "cadence": "Weekly full-lengths plus targeted review and performance sets.",
            "recommendation": "Schedule one full-length this week and review it thoroughly.",
        }
    return {
        "phase": "early",
        "cadence": "About one full-length per week is plenty; review quality matters more than volume.",
        "recommendation": "Focus on coverage and performance sets; full-lengths can be occasional.",
    }


def _phase(days_left: int | None) -> str:
    """Study phase from the exam countdown. Drives how the roadmap is composed:
    foundation = lessons/coverage, sharpen = mixed + full-lengths, final = mostly
    full run-throughs and Mini-MCATs."""
    if days_left is None:
        return "foundation"
    if days_left <= 14:
        return "final"
    if days_left <= 45:
        return "sharpen"
    return "foundation"


_PHASE_LABEL = {
    "foundation": "Foundation — build coverage",
    "sharpen": "Sharpening — mixed practice + full-lengths",
    "final": "Final stretch — full run-throughs",
}


def required_complete(plan: dict[str, Any]) -> bool:
    required = [b for b in plan.get("blocks", []) if b.get("required")]
    return bool(required) and all(b.get("completed") for b in required)


def _today() -> str:
    return datetime.date.today().isoformat()


def _days_until_exam(profile: dict[str, Any]) -> int | None:
    exam_date = profile.get("exam_date")
    if not exam_date:
        return None
    try:
        exam = datetime.date.fromisoformat(exam_date)
    except ValueError:
        return None
    return (exam - datetime.date.today()).days


def build_daily_plan(col: anki.collection.Collection) -> dict[str, Any]:
    """Build today's ordered roadmap blocks based on the profile and scores."""
    profile = store.get_profile(col)
    target = max(15, int(profile.get("daily_minutes", DEFAULT_DAILY_MINUTES)))
    days_left = _days_until_exam(profile)
    phase = _phase(days_left)
    near_exam = phase == "final"
    # Fixed section order so the roadmap is DETERMINISTIC and identical on desktop
    # and iOS (both build the same blocks with the same stable keys, which is what
    # lets progress sync by key across devices).
    order = [
        schema.SECTION_BB,
        schema.SECTION_CP,
        schema.SECTION_PS,
        schema.SECTION_CARS,
    ]
    primary = order[0]
    secondary = order[1]

    blocks: list[dict[str, Any]] = []
    used = 0
    occ: dict[str, int] = {}

    def add(item: dict[str, Any]) -> None:
        nonlocal used
        base = item["key_base"]
        occ[base] = occ.get(base, 0) + 1
        n = occ[base]
        minutes = min(MAX_BLOCK_MINUTES, int(item["minutes"]))
        blocks.append(
            _block(
                key=f"{base}-{n}",
                kind=item["kind"],
                section=item["section"],
                mode=item["mode"],
                label=item["label"] + (f" #{n}" if n > 1 else ""),
                minutes=minutes,
                required=True,
                meta=dict(item.get("meta", {})),
            )
        )
        used += minutes

    # Larger Mini-MCATs when more time is available.
    mini_count = 20 if target >= 60 else (16 if target >= 40 else 12)

    def mini() -> dict[str, Any]:
        return {
            "key_base": "mini-mcat",
            "kind": "mini_mcat",
            "section": None,
            "mode": schema.MODE_PERFORMANCE,
            "label": "Mini-MCAT",
            "minutes": 15,
            "meta": {"count": mini_count},
        }

    def full_len() -> dict[str, Any]:
        return {
            "key_base": "full-length",
            "kind": "full_length_review",
            "section": None,
            "mode": schema.MODE_STRATEGY,
            "label": "Full-Length Run-Through",
            "minutes": 20,
            "meta": {},
        }

    def maintenance() -> dict[str, Any]:
        return {
            "key_base": "maintenance",
            "kind": "memory",
            "section": None,
            "mode": schema.MODE_MEMORY,
            "label": "Memory Maintenance",
            "minutes": 10,
            "meta": {"count": 12},
        }

    # The block MIX shifts with the exam phase, so the roadmap visibly changes as
    # test day nears: Foundation = per-section lessons (application + recall);
    # Sharpening = fewer lessons + full-lengths; Final = mostly Mini-MCATs and
    # full run-throughs with only short maintenance. CARS is MCQ practice (the
    # AI-dependent debate is deferred).
    def application(sec: str) -> dict[str, Any]:
        label = (
            "CARS Practice"
            if sec == schema.SECTION_CARS
            else f"{_short(sec)} Application"
        )
        return {
            "key_base": f"{sec}-application",
            "kind": "performance",
            "section": sec,
            "mode": schema.MODE_PERFORMANCE,
            "label": label,
            "minutes": 15,
            "meta": {"count": 6},
        }

    def recall(sec: str) -> dict[str, Any]:
        return {
            "key_base": f"{sec}-recall",
            "kind": "memory",
            "section": sec,
            "mode": schema.MODE_MEMORY,
            "label": f"{_short(sec)} Recall",
            "minutes": 10,
            "meta": {"count": 10},
        }

    # Always open the day with a Mini-MCAT (real exam form).
    add(mini())

    menu: list[dict[str, Any]] = []
    if phase == "final":
        # Final stretch: full run-throughs + Mini-MCATs only. Flashcards/lessons
        # are disabled this close to test day.
        menu = [mini(), full_len(), mini(), full_len()]
    elif phase == "sharpen":
        menu = [
            mini(),
            application(schema.SECTION_BB),
            application(schema.SECTION_CP),
            full_len(),
            recall(schema.SECTION_BB),
            maintenance(),
        ]
    else:
        for sec in order:
            menu.append(application(sec))
            if sec != schema.SECTION_CARS:
                menu.append(recall(sec))
        menu.append(maintenance())

    # Fill the day with ~target minutes of blocks, cycling the menu if needed.
    idx = 0
    while used < target - 4 and len(blocks) < _MAX_BLOCKS:
        item = menu[idx % len(menu)]
        if used + min(MAX_BLOCK_MINUTES, int(item["minutes"])) > target + 6:
            break
        add(item)
        idx += 1

    plan = {
        "date": _today(),
        "exam_date": profile.get("exam_date"),
        "days_until_exam": days_left,
        "phase": phase,
        "phase_label": _PHASE_LABEL[phase],
        "daily_minutes": target,
        "target_minutes": target,
        "planned_minutes": used,
        "primary_section": primary,
        "secondary_section": secondary,
        "near_exam": near_exam,
        "full_length": full_length_guidance(days_left),
        "blocks": blocks,
    }
    store.set_plan(col, plan)
    return plan


def get_or_build_plan(col: anki.collection.Collection) -> dict[str, Any]:
    plan = store.get_plan(col)
    profile = store.get_profile(col)
    target = int(profile.get("daily_minutes", DEFAULT_DAILY_MINUTES))
    stale = (
        plan is None
        or plan.get("date") != _today()
        or plan.get("target_minutes") is None
        or plan.get("daily_minutes") != target
        or plan.get("exam_date") != profile.get("exam_date")
        or "phase" not in plan
        # Older plans predate stable block keys; rebuild so progress can sync.
        or any("key" not in b for b in plan.get("blocks", []))
    )
    if stale:
        return build_daily_plan(col)
    return plan


def complete_block(
    col: anki.collection.Collection,
    block_id: str,
    *,
    score: dict[str, int] | None = None,
) -> dict[str, Any]:
    """Mark a block complete. `score` = {correct, total} records how the student
    did on the block (shown as a small tally on the roadmap); ignored when the
    block has no numeric score (e.g. a CARS debate) or total is 0."""
    plan = get_or_build_plan(col)
    for block in plan["blocks"]:
        if block["id"] == block_id:
            block["completed"] = True
            if score and int(score.get("total", 0)) > 0:
                total = int(score["total"])
                correct = max(0, min(total, int(score.get("correct", 0))))
                block["score"] = {"correct": correct, "total": total}
            break
    store.set_plan(col, plan)
    _maybe_award_streak(col, plan)
    return plan


def _maybe_award_streak(col: anki.collection.Collection, plan: dict[str, Any]) -> None:
    required = [b for b in plan["blocks"] if b["required"]]
    if required and all(b.get("completed") for b in required):
        streak = store.get_streak(col)
        today = _today()
        if streak.get("last_completed_date") == today:
            return
        yesterday = (datetime.date.today() - datetime.timedelta(days=1)).isoformat()
        if streak.get("last_completed_date") == yesterday:
            streak["count"] = int(streak.get("count", 0)) + 1
        else:
            streak["count"] = 1
        streak["last_completed_date"] = today
        store.set_streak(col, streak)


def _block(
    *,
    key: str,
    kind: str,
    section: str | None,
    mode: str,
    label: str,
    minutes: int,
    required: bool,
    meta: dict[str, Any],
) -> dict[str, Any]:
    return {
        "id": uuid.uuid4().hex,
        "key": key,
        "kind": kind,
        "section": section,
        "mode": mode,
        "label": label,
        "minutes": min(MAX_BLOCK_MINUTES, minutes),
        "required": required,
        "completed": False,
        # {correct, total} filled in on completion; drives the roadmap's per-node
        # score tally. None until the block is finished (or for unscored blocks).
        "score": None,
        "meta": meta,
    }


def _short(section: str) -> str:
    return {
        schema.SECTION_BB: "Bio/Biochem",
        schema.SECTION_CP: "Chem/Phys",
        schema.SECTION_PS: "Psych/Soc",
        schema.SECTION_CARS: "CARS",
    }.get(section, section)
