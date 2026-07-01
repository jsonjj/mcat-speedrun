# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""The MCAT topic taxonomy (official content outline).

For now this is a scaffold loaded from `data/taxonomy.json`. When the real AAMC
content outline is available, swap the data file (or call `load_taxonomy` with a
custom path) and the rest of the app keeps working: topic ids, section mapping
and weights all flow from here.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

_DATA_PATH = Path(__file__).with_name("data") / "taxonomy.json"


@dataclass(frozen=True)
class Topic:
    id: str
    name: str
    section: str
    weight: float


@dataclass(frozen=True)
class Taxonomy:
    topics: tuple[Topic, ...]

    def by_section(self, section: str) -> list[Topic]:
        return [t for t in self.topics if t.section == section]

    def topic_ids(self, section: str | None = None) -> list[str]:
        if section is None:
            return [t.id for t in self.topics]
        return [t.id for t in self.topics if t.section == section]

    def get(self, topic_id: str) -> Topic | None:
        for t in self.topics:
            if t.id == topic_id:
                return t
        return None

    def section_weight(self, section: str) -> float:
        return sum(t.weight for t in self.by_section(section))


def load_taxonomy(path: Path | None = None) -> Taxonomy:
    """Load a taxonomy from disk (uncached when a custom path is provided)."""
    if path is None:
        return _load_default_taxonomy()
    return _parse_taxonomy(json.loads(Path(path).read_text(encoding="utf-8")))


@lru_cache(maxsize=1)
def _load_default_taxonomy() -> Taxonomy:
    return _parse_taxonomy(json.loads(_DATA_PATH.read_text(encoding="utf-8")))


def _parse_taxonomy(raw: dict) -> Taxonomy:
    topics: list[Topic] = []
    for section, payload in raw.get("sections", {}).items():
        for topic in payload.get("topics", []):
            topics.append(
                Topic(
                    id=topic["id"],
                    name=topic["name"],
                    section=section,
                    weight=float(topic.get("weight", 1.0)),
                )
            )
    return Taxonomy(topics=tuple(topics))
