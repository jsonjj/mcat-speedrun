# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""MCAT Speedrun: a non-AI, AI-ready MCAT preparation layer built on top of Anki.

This package adds MCAT-specific structure on top of stock Anki using only
existing collection primitives:

- `schema`:   canonical tags/fields and the MCAT notetypes.
- `taxonomy`: the official-outline topic map (scaffold for now).
- `store`:    a thin data-access layer over the synced collection config
              (`mcat:*` keys) for attempts, plans, scores and calibration.
- `content`:  the content-pack format and seed-deck loader.
- `scoring`:  the transparent (AI-off) memory/performance/readiness model.

Nothing in here calls AI. Every field that AI will later use (reasoning text,
source ids, mistake labels, calibration) is captured now so AI can plug in
without a redesign.
"""

from __future__ import annotations

from anki.mcat import schema, scoring, store, taxonomy

__all__ = ["schema", "scoring", "store", "taxonomy"]
