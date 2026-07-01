# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

"""Firebase sync for the desktop app.

Signs in against Firebase Auth (email/password) and reads/writes the same
`users/{uid}` Firestore document the iOS app uses, so profile + streak stay in
sync across devices. Pure stdlib (urllib) — no extra dependencies.

Only the fields that make sense across both apps are synced (name, email, exam
date, daily minutes, streak). We write with an updateMask so we never clobber
fields the phone owns (e.g. its per-device roadmap progress). All network calls
are best-effort: failures return an error/None and never raise into the app.
"""

from __future__ import annotations

import datetime
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import TYPE_CHECKING, Any

from anki.mcat import schema, store

if TYPE_CHECKING:
    import anki.collection

KEY_FIREBASE = "mcat:firebase"  # session: {uid, refresh_token, id_token, expiry}
_CONFIG_PATH = Path(__file__).with_name("firebase.json")
_IDENTITY = "https://identitytoolkit.googleapis.com/v1"
_SECURETOKEN = "https://securetoken.googleapis.com/v1"
_FIRESTORE = "https://firestore.googleapis.com/v1"


def _config() -> dict[str, Any]:
    try:
        return json.loads(_CONFIG_PATH.read_text(encoding="utf-8"))
    except Exception:
        return {}


def available() -> bool:
    return bool(_config().get("apiKey") and _config().get("projectId"))


def _post_json(url: str, payload: dict[str, Any]) -> tuple[dict[str, Any] | None, str]:
    """POST JSON, return (parsed, error). error is "" on success."""
    try:
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            url, data=data, headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode("utf-8")), ""
    except urllib.error.HTTPError as err:
        try:
            body = json.loads(err.read().decode("utf-8"))
            msg = body.get("error", {}).get("message", str(err))
        except Exception:
            msg = f"HTTP {err.code}"
        return None, _friendly(msg)
    except Exception as err:  # network down, timeout, etc.
        return None, f"Network error: {err}"


def _friendly(code: str) -> str:
    return {
        "EMAIL_NOT_FOUND": "No account with that email.",
        "INVALID_PASSWORD": "Incorrect password.",
        "INVALID_LOGIN_CREDENTIALS": "Incorrect email or password.",
        "EMAIL_EXISTS": "An account with that email already exists.",
        "WEAK_PASSWORD : Password should be at least 6 characters": (
            "Password must be at least 6 characters."
        ),
    }.get(code, code)


# Auth
#############################################################################


def _auth(
    col: anki.collection.Collection, endpoint: str, email: str, password: str
) -> tuple[dict[str, Any] | None, str]:
    cfg = _config()
    key = cfg.get("apiKey")
    if not key:
        return None, "Firebase is not configured."
    url = f"{_IDENTITY}/accounts:{endpoint}?key={key}"
    data, err = _post_json(
        url, {"email": email, "password": password, "returnSecureToken": True}
    )
    if err or not data:
        return None, err or "Sign-in failed."
    session = {
        "uid": data["localId"],
        "id_token": data["idToken"],
        "refresh_token": data["refreshToken"],
        "expiry": int(time.time()) + int(data.get("expiresIn", "3600")) - 60,
        "email": email,
    }
    col.set_config(KEY_FIREBASE, session)
    return session, ""


def sign_in(
    col: anki.collection.Collection, email: str, password: str
) -> tuple[dict[str, Any] | None, str]:
    return _auth(col, "signInWithPassword", email, password)


def sign_up(
    col: anki.collection.Collection, email: str, password: str
) -> tuple[dict[str, Any] | None, str]:
    return _auth(col, "signUp", email, password)


def sign_out(col: anki.collection.Collection) -> None:
    col.set_config(KEY_FIREBASE, None)


def _session(col: anki.collection.Collection) -> dict[str, Any] | None:
    s = col.get_config(KEY_FIREBASE, None)
    return s if isinstance(s, dict) and s.get("uid") else None


def _valid_token(col: anki.collection.Collection) -> str | None:
    """Return a live id token, refreshing if needed."""
    s = _session(col)
    if not s:
        return None
    if int(time.time()) < int(s.get("expiry", 0)):
        return s["id_token"]
    cfg = _config()
    key = cfg.get("apiKey")
    try:
        body = urllib.parse.urlencode(
            {"grant_type": "refresh_token", "refresh_token": s["refresh_token"]}
        ).encode("utf-8")
        req = urllib.request.Request(
            f"{_SECURETOKEN}/token?key={key}",
            data=body,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        s["id_token"] = data["id_token"]
        s["refresh_token"] = data["refresh_token"]
        s["expiry"] = int(time.time()) + int(data.get("expires_in", "3600")) - 60
        col.set_config(KEY_FIREBASE, s)
        return s["id_token"]
    except Exception:
        return None


# Firestore <-> local
#############################################################################


def _to_fields(data: dict[str, Any]) -> dict[str, Any]:
    fields: dict[str, Any] = {}
    for key, value in data.items():
        if value is None:
            continue
        if isinstance(value, bool):
            fields[key] = {"booleanValue": value}
        elif isinstance(value, int):
            fields[key] = {"integerValue": str(value)}
        elif isinstance(value, float):
            fields[key] = {"doubleValue": value}
        else:
            fields[key] = {"stringValue": str(value)}
    return fields


def _from_fields(fields: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for key, val in (fields or {}).items():
        if "integerValue" in val:
            out[key] = int(val["integerValue"])
        elif "doubleValue" in val:
            out[key] = float(val["doubleValue"])
        elif "booleanValue" in val:
            out[key] = bool(val["booleanValue"])
        elif "stringValue" in val:
            out[key] = val["stringValue"]
    return out


# The subset of fields synced across desktop + iOS. examDate is a date-only
# string ("YYYY-MM-DD") so it round-trips with iOS; roadmap progress is a
# date-scoped list of completed block keys (slugs). Study is now the FULL engine
# event log, owner-scoped (`mcatLogDesktop` vs `mcatLogIos`): each device writes
# its own log and reads the other, and the engine's replay-union merge combines
# them — giving per-card review + scheduling sync with no conflicts.
def _local_payload(col: anki.collection.Collection) -> dict[str, Any]:
    from anki.mcat import planner

    profile = store.get_profile(col)
    streak = store.get_streak(col)
    plan = planner.get_or_build_plan(col)
    completed = [
        b["key"]
        for b in plan.get("blocks", [])
        if b.get("completed") and b.get("key")
    ]
    exam = profile.get("exam_date")
    return {
        "name": profile.get("name") or "",
        "email": profile.get("email") or "",
        "examDate": (str(exam)[:10] if exam else ""),
        "dailyMinutes": int(profile.get("daily_minutes", 120)),
        "streak": int(streak.get("count", 0)),
        "streakDate": streak.get("last_completed_date") or "",
        "completedBlocksDesktop": json.dumps(completed),
        "roadmapDate": plan.get("date") or "",
        "mcatLogDesktop": json.dumps(store.get_mcat_log(col)),
        "diagnosticKind": profile.get("diagnostic_kind") or "",
    }


def push(col: anki.collection.Collection) -> str:
    """Write local profile/streak up to Firestore (merge, never clobbering the
    phone's fields). Returns "" on success or an error string."""
    token = _valid_token(col)
    session = _session(col)
    if not token or not session:
        return "Not signed in."
    payload = _local_payload(col)
    fields = _to_fields(payload)
    cfg = _config()
    # Mask only the fields we actually send, so we never clobber remote-only data.
    masks = "&".join(
        f"updateMask.fieldPaths={urllib.parse.quote(k)}" for k in fields
    )
    url = (
        f"{_FIRESTORE}/projects/{cfg['projectId']}/databases/(default)/documents/"
        f"users/{session['uid']}?{masks}"
    )
    try:
        data = json.dumps({"fields": fields}).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=data,
            method="PATCH",
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {token}",
            },
        )
        urllib.request.urlopen(req, timeout=15).read()
        return ""
    except Exception as err:
        return f"Sync push failed: {err}"


def pull(col: anki.collection.Collection) -> str:
    """Read the Firestore doc and apply remote profile/streak locally. Returns
    "" on success, or an error string (also "" when there's simply no doc yet)."""
    token = _valid_token(col)
    session = _session(col)
    if not token or not session:
        return "Not signed in."
    cfg = _config()
    url = (
        f"{_FIRESTORE}/projects/{cfg['projectId']}/databases/(default)/documents/"
        f"users/{session['uid']}"
    )
    try:
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            doc = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as err:
        if err.code == 404:
            # No remote doc yet — seed it from local state.
            push(col)
            return ""
        return f"Sync pull failed: HTTP {err.code}"
    except Exception as err:
        return f"Sync pull failed: {err}"

    remote = _from_fields(doc.get("fields", {}))
    updates: dict[str, Any] = {}
    if remote.get("name"):
        updates["name"] = remote["name"]
    if "examDate" in remote:
        # Tolerate a full ISO datetime from older clients; keep date-only.
        ed = str(remote["examDate"])[:10] if remote["examDate"] else None
        updates["exam_date"] = ed
    if "dailyMinutes" in remote:
        updates["daily_minutes"] = int(remote["dailyMinutes"])
    if remote.get("diagnosticKind"):
        updates["diagnostic_kind"] = remote["diagnosticKind"]
    if updates:
        store.update_profile(col, **updates)
    if "streak" in remote or "streakDate" in remote:
        streak = store.get_streak(col)
        if "streak" in remote:
            streak["count"] = int(remote["streak"])
        if remote.get("streakDate"):
            streak["last_completed_date"] = remote["streakDate"]
        store.set_streak(col, streak)

    # The phone's full engine log, so desktop scores + scheduling reflect
    # combined per-card study (merged via the engine's replay-union).
    if "mcatLogIos" in remote:
        try:
            parsed = json.loads(remote["mcatLogIos"]) if remote["mcatLogIos"] else {}
        except (ValueError, TypeError):
            parsed = {}
        store.set_remote_mcat_log(col, parsed if isinstance(parsed, dict) else {})

    # Roadmap progress: apply the remote completed-block keys, but only when the
    # remote roadmap is for today (so yesterday's progress never marks today's
    # blocks done). The plan is (re)built first so it reflects any exam-date /
    # daily-minute change we just pulled.
    from anki.mcat import planner

    today = datetime.date.today().isoformat()
    if remote.get("roadmapDate") == today and "completedBlocksIos" in remote:
        try:
            keys = set(json.loads(remote["completedBlocksIos"]))
        except (ValueError, TypeError):
            keys = set()
        plan = planner.get_or_build_plan(col)
        changed = False
        # Union in the phone's completed blocks; never un-complete local progress
        # (a new day resets via a fresh plan, so stale data can't wipe today).
        for block in plan.get("blocks", []):
            if not block.get("completed") and block.get("key") in keys:
                block["completed"] = True
                changed = True
        if changed:
            store.set_plan(col, plan)
    return ""
