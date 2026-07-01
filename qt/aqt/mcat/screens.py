# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Make MCAT Speedrun the main window.

Instead of opening a separate dialog, this embeds a dedicated API-enabled
webview as the central content of Anki's main window and hides Anki's own
chrome (top toolbar with Decks/Add/Browse/Stats/Sync, the deck-browser web, and
the bottom bar). The result: the app launches straight into the MCAT
experience, which handles onboarding, the placement test, the daily roadmap and
everything else through its own in-app navigation.
"""

from __future__ import annotations

import aqt
import aqt.main
from aqt import gui_hooks
from aqt.qt import QTimer
from aqt.webview import AnkiWebView, AnkiWebViewKind

# The embedded MCAT home view (one per app), parented to the main window.
_home_view: AnkiWebView | None = None
_loaded = False


def setup_mcat(mw: aqt.main.AnkiQt) -> None:
    """Replace Anki's home screen with the embedded MCAT app."""
    global _home_view
    if _home_view is not None:
        return

    view = AnkiWebView(mw, kind=AnkiWebViewKind.MCAT)
    view.setObjectName("mcatHome")
    mw.mainLayout.addWidget(view)
    view.hide()
    _home_view = view

    _hide_anki_chrome(mw)
    _hide_deck_menu_actions(mw)

    gui_hooks.collection_did_load.append(lambda _col: _on_collection_load(mw))
    gui_hooks.state_did_change.append(lambda *_a: _keep_home(mw))


def _noop(*_a: object, **_k: object) -> None:
    return None


def _hide_anki_chrome(mw: aqt.main.AnkiQt) -> None:
    # The deck browser asynchronously re-shows AND re-sizes its toolbar/bottom
    # bar (the Get Shared / Create Deck / Import File buttons and the top
    # toolbar) after we hide them, so a plain hide() isn't enough — a hidden
    # widget that Anki later calls setFixedHeight()+show() on reappears as an
    # empty grey band. We hide each widget, force its height to zero, then
    # neutralize every method Anki uses to reveal or grow them again.
    for widget in (mw.toolbarWeb, mw.web, mw.bottomWeb):
        widget.hide()
        widget.setFixedHeight(0)
        widget.setMaximumHeight(0)
        setattr(widget, "show", _noop)
        setattr(widget, "setVisible", _noop)
        setattr(widget, "setHidden", _noop)
        setattr(widget, "setFixedHeight", _noop)
        setattr(widget, "setMaximumHeight", _noop)
        # TopWebView/BottomWebView resize themselves via this height callback.
        setattr(widget, "_onHeight", _noop)


def _hide_deck_menu_actions(mw: aqt.main.AnkiQt) -> None:
    """Hide Anki's deck-file features. MCAT Speedrun ships its own deck, so the
    Get Shared / Create Deck / Import File flows (deck-browser buttons, already
    hidden) and the File > Import/Export menu items are removed."""
    for name in ("actionImport", "actionExport"):
        action = getattr(mw.form, name, None)
        if action is not None:
            action.setVisible(False)


def _on_collection_load(mw: aqt.main.AnkiQt) -> None:
    # Defer slightly so the media server and window are fully ready.
    QTimer.singleShot(50, lambda: _enter_home(mw))


def _enter_home(mw: aqt.main.AnkiQt) -> None:
    global _loaded
    if _home_view is None:
        return
    _hide_anki_chrome(mw)
    _home_view.show()
    # Load (or reload) the router once the collection is open.
    _home_view.load_sveltekit_page("mcat")
    _loaded = True


def _keep_home(mw: aqt.main.AnkiQt) -> None:
    """Keep the MCAT view in front whenever Anki changes screen state."""
    if _home_view is None or not _loaded:
        return
    _hide_anki_chrome(mw)
    _home_view.show()
