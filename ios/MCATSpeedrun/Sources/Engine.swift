// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// Swift wrapper over the shared Rust engine's C ABI (mcat_ffi.xcframework).
// This is the SAME engine the desktop uses — scoring, FSRS scheduling and the
// replay-union merge all run here, so both apps compute identical results.

import Foundation
import mcat_ffi

enum Engine {
    /// Version string from the shared Rust engine.
    static func version() -> String {
        consume(mcat_engine_version())
    }

    /// Compute the three scores. `state`/`coverage`/`external` are JSON; `diag`
    /// is the diagnostic kind ("" for none). Returns a Scores JSON string.
    static func scores(state: String, coverage: String, external: String, diag: String)
        -> String
    {
        consume(mcat_scores(state, coverage, external, diag))
    }

    /// Replay-union merge two McatState JSON strings (append events or reconcile
    /// a synced state). Returns the merged McatState JSON.
    static func merge(state: String, other: String) -> String {
        consume(mcat_merge(state, other))
    }

    /// JSON array of card keys due at `nowTs`, given `allKeys` (JSON array).
    static func dueCards(state: String, allKeys: String, nowTs: Int64, retention: Float)
        -> String
    {
        consume(mcat_due_cards(state, allKeys, nowTs, retention))
    }

    /// Take ownership of a C string returned by the engine and free it.
    private static func consume(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
        guard let ptr else { return "" }
        defer { mcat_string_free(ptr) }
        return String(cString: ptr)
    }
}
