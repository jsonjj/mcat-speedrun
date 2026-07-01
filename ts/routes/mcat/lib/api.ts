// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// Thin JSON transport to the MCAT Speedrun Python endpoints registered in
// aqt/mediasrv.py. We use plain JSON (not protobuf) for the MCAT-specific data;
// the Rust Mastery Query is consumed server-side by the scoring layer.

export async function postJson<T>(endpoint: string, payload: unknown = {}): Promise<T> {
    // Anki's mediasrv only allows same-origin POSTs with this content type; the
    // body is still JSON, read server-side via flask.request.data.
    const response = await fetch(`/_anki/${endpoint}`, {
        method: "POST",
        headers: { "Content-Type": "application/binary" },
        body: JSON.stringify(payload),
    });
    if (!response.ok) {
        const text = await response.text();
        throw new Error(`${endpoint} failed (${response.status}): ${text}`);
    }
    return (await response.json()) as T;
}
