# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Desktop (Qt) glue for MCAT Speedrun.

`endpoints` exposes JSON POST handlers that the Svelte pages call via
`/_anki/<endpoint>`; `screens` opens those pages and wires the MCAT menu.
"""

from __future__ import annotations
