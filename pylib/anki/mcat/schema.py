# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Canonical MCAT tag/field schema and notetype definitions.

The schema maps every card and question onto the official MCAT sections and
topics using Anki tags, and stores AI-ready fields (source id, reasoning,
explanation, mistake labels, variants) on the notes themselves. This keeps the
data inside the synced collection, so sync/undo/integrity work for free.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import anki.collection
    import anki.models

# Sections
#############################################################################

# Official MCAT section codes used throughout the app.
SECTION_BB = "bb"  # Biological and Biochemical Foundations of Living Systems
SECTION_CP = "cp"  # Chemical and Physical Foundations of Biological Systems
SECTION_PS = "ps"  # Psychological, Social, and Biological Foundations of Behavior
SECTION_CARS = "cars"  # Critical Analysis and Reasoning Skills

SECTIONS: tuple[str, ...] = (SECTION_BB, SECTION_CP, SECTION_PS, SECTION_CARS)

SECTION_NAMES: dict[str, str] = {
    SECTION_BB: "Biological and Biochemical Foundations of Living Systems",
    SECTION_CP: "Chemical and Physical Foundations of Biological Systems",
    SECTION_PS: "Psychological, Social, and Biological Foundations of Behavior",
    SECTION_CARS: "Critical Analysis and Reasoning Skills",
}

# Card types and modes
#############################################################################

CARD_TYPE_MEMORY = "memory"
CARD_TYPE_PERFORMANCE = "performance"

MODE_MEMORY = "memory"
MODE_PERFORMANCE = "performance"
MODE_DEBATE = "debate"
MODE_TIMING = "timing"
MODE_STRATEGY = "strategy"

PHASE_DIAGNOSTIC = "diagnostic"
PHASE_DAILY = "daily"
PHASE_FULL_LENGTH = "full_length"
PHASE_REVIEW = "review"

CONFIDENCE_CERTAIN = "certain"
CONFIDENCE_LEANING = "leaning"
CONFIDENCE_GUESSING = "guessing"
CONFIDENCE_LEVELS: tuple[str, ...] = (
    CONFIDENCE_CERTAIN,
    CONFIDENCE_LEANING,
    CONFIDENCE_GUESSING,
)

# Tag prefixes
#############################################################################

TAG_EXAM = "exam:mcat"
TAG_SECTION_PREFIX = "section:"
TAG_TOPIC_PREFIX = "topic:"
TAG_CARD_TYPE_PREFIX = "card_type:"
TAG_DIFFICULTY_PREFIX = "difficulty:"
TAG_SOURCE_PREFIX = "source:"
TAG_WEIGHT_PREFIX = "official_outline_weight:"
TAG_PHASE_PREFIX = "phase:"
TAG_MODE_PREFIX = "mode:"
TAG_AI_READY = "ai_ready:true"

MCAT_DECK_NAME = "MCAT Speedrun"


def build_tags(
    *,
    section: str,
    topic_ids: list[str],
    card_type: str,
    difficulty: int,
    source_id: str,
    mode: str,
    phase: str | None = None,
    official_outline_weight: float | None = None,
    ai_ready: bool = False,
) -> list[str]:
    """Build the canonical MCAT tag list for a note."""
    tags = [
        TAG_EXAM,
        f"{TAG_SECTION_PREFIX}{section}",
        f"{TAG_CARD_TYPE_PREFIX}{card_type}",
        f"{TAG_DIFFICULTY_PREFIX}{difficulty}",
        f"{TAG_SOURCE_PREFIX}{source_id}",
        f"{TAG_MODE_PREFIX}{mode}",
    ]
    tags += [f"{TAG_TOPIC_PREFIX}{tid}" for tid in topic_ids]
    if phase is not None:
        tags.append(f"{TAG_PHASE_PREFIX}{phase}")
    if official_outline_weight is not None:
        tags.append(f"{TAG_WEIGHT_PREFIX}{official_outline_weight}")
    if ai_ready:
        tags.append(TAG_AI_READY)
    return tags


def section_search(section: str) -> str:
    """An Anki search string limiting to one MCAT section."""
    return f'"tag:{TAG_EXAM}" "tag:{TAG_SECTION_PREFIX}{section}"'


def topic_search(topic_id: str) -> str:
    return f'"tag:{TAG_TOPIC_PREFIX}{topic_id}"'


def card_type_search(card_type: str) -> str:
    return f'"tag:{TAG_CARD_TYPE_PREFIX}{card_type}"'


def parse_tag_value(tags: list[str], prefix: str) -> str | None:
    for tag in tags:
        if tag.startswith(prefix):
            value = tag[len(prefix) :]
            if value:
                return value
    return None


def parse_topics(tags: list[str]) -> list[str]:
    return [t[len(TAG_TOPIC_PREFIX) :] for t in tags if t.startswith(TAG_TOPIC_PREFIX)]


def parse_difficulty(tags: list[str]) -> int:
    value = parse_tag_value(tags, TAG_DIFFICULTY_PREFIX)
    try:
        return int(value) if value is not None else 3
    except ValueError:
        return 3


# Notetypes
#############################################################################

NOTETYPE_MEMORY = "MCAT Memory"
NOTETYPE_PERFORMANCE = "MCAT Performance"
NOTETYPE_CARS = "MCAT CARS"

# Shared AI-ready fields appended to every MCAT notetype. These are empty until
# AI exists, but their presence means AI can later populate explanations,
# reasoning diagnoses and safe variants without a schema migration.
_AI_READY_FIELDS = [
    "SourceId",
    "Reasoning",
    "Explanation",
    "MistakeTypes",
    "Variants",
    "AiReady",
]

_MEMORY_FIELDS = ["Front", "Back", "TopicIds", "Section"] + _AI_READY_FIELDS
_PERFORMANCE_FIELDS = [
    "Question",
    "ChoiceA",
    "ChoiceB",
    "ChoiceC",
    "ChoiceD",
    "ChoiceE",
    "CorrectChoice",
    "TopicIds",
    "Section",
] + _AI_READY_FIELDS
_CARS_FIELDS = [
    "Passage",
    "AuthorClaim",
    "DebatePrompts",
    "SkillType",
    "Section",
] + _AI_READY_FIELDS

_MCAT_CSS = """
.card { font-family: -apple-system, system-ui, sans-serif; font-size: 18px;
        color: #1a2332; background: #ffffff; line-height: 1.5; padding: 1rem; }
.mcat-q { font-weight: 600; margin-bottom: 0.75rem; }
.mcat-choice { padding: 0.35rem 0; }
.mcat-meta { margin-top: 1rem; color: #6b7280; font-size: 13px; }
.nightMode.card { color: #e6e9ef; background: #11151c; }
"""


def _memory_templates() -> list[tuple[str, str, str]]:
    return [
        (
            "Card 1",
            "{{Front}}",
            '{{FrontSide}}<hr id="answer">{{Back}}'
            '<div class="mcat-meta">{{Section}} · {{TopicIds}}</div>',
        )
    ]


def _performance_templates() -> list[tuple[str, str, str]]:
    # Fallback rendering for the normal reviewer; the Mini-MCAT UI reads the
    # fields directly instead of using this template.
    q = (
        '<div class="mcat-q">{{Question}}</div>'
        '<div class="mcat-choice">A. {{ChoiceA}}</div>'
        '<div class="mcat-choice">B. {{ChoiceB}}</div>'
        '<div class="mcat-choice">C. {{ChoiceC}}</div>'
        '<div class="mcat-choice">D. {{ChoiceD}}</div>'
    )
    a = (
        '{{FrontSide}}<hr id="answer">'
        "<b>Correct: {{CorrectChoice}}</b>"
        "<div>{{Explanation}}</div>"
        '<div class="mcat-meta">{{Section}} · {{TopicIds}}</div>'
    )
    return [("Card 1", q, a)]


def _cars_templates() -> list[tuple[str, str, str]]:
    q = '<div class="mcat-q">CARS passage</div><div>{{Passage}}</div>'
    a = (
        '{{FrontSide}}<hr id="answer">'
        "<b>Author's claim:</b> {{AuthorClaim}}"
        '<div class="mcat-meta">Skill: {{SkillType}}</div>'
    )
    return [("Card 1", q, a)]


def _build_notetype(
    col: anki.collection.Collection,
    name: str,
    fields: list[str],
    templates: list[tuple[str, str, str]],
) -> anki.models.NotetypeDict:
    mm = col.models
    nt = mm.new(name)
    for field_name in fields:
        mm.add_field(nt, mm.new_field(field_name))
    for tmpl_name, qfmt, afmt in templates:
        tmpl = mm.new_template(tmpl_name)
        tmpl["qfmt"] = qfmt
        tmpl["afmt"] = afmt
        mm.add_template(nt, tmpl)
    nt["css"] = _MCAT_CSS
    return nt


def ensure_mcat_notetypes(
    col: anki.collection.Collection,
) -> dict[str, anki.models.NotetypeId]:
    """Create the MCAT notetypes if they don't yet exist; return name -> id."""
    import anki.models

    definitions = [
        (NOTETYPE_MEMORY, _MEMORY_FIELDS, _memory_templates()),
        (NOTETYPE_PERFORMANCE, _PERFORMANCE_FIELDS, _performance_templates()),
        (NOTETYPE_CARS, _CARS_FIELDS, _cars_templates()),
    ]
    result: dict[str, anki.models.NotetypeId] = {}
    for name, fields, templates in definitions:
        existing = col.models.by_name(name)
        if existing is not None:
            result[name] = anki.models.NotetypeId(existing["id"])
            continue
        nt = _build_notetype(col, name, fields, templates)
        out = col.models.add_dict(nt)
        result[name] = anki.models.NotetypeId(out.id)
    return result


def ensure_mcat_deck(col: anki.collection.Collection) -> int:
    """Create (or fetch) the top-level MCAT Speedrun deck; return its id."""
    return col.decks.id(MCAT_DECK_NAME)
