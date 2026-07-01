// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// C interface for the MCAT Speedrun engine (Rust). Bundled into the
// mcat_ffi.xcframework so the SwiftUI app can call into rslib.

#ifndef MCAT_FFI_H
#define MCAT_FFI_H

// Returns the engine version. Caller owns the string and must release it with
// mcat_string_free().
char *mcat_engine_version(void);

// Compute the three scores. All args are JSON strings (see rslib mcat_core::api):
//   state    - the McatState (event logs)
//   coverage - {"bb":[covered,total], ...}
//   external - the other device's aggregate, or "" for none
//   diag     - diagnostic kind ("standard"/"best_estimate"/...) or "" for none
// Returns a JSON Scores string; caller frees it with mcat_string_free().
char *mcat_scores(const char *state, const char *coverage, const char *external,
                  const char *diag);

// Replay-union merge of two McatState JSON strings (append local events or
// reconcile a synced state). Returns merged McatState JSON; free with
// mcat_string_free().
char *mcat_merge(const char *state, const char *other);

// Returns a JSON array of card keys due at now_ts, given all_keys (JSON array).
// Free the result with mcat_string_free().
char *mcat_due_cards(const char *state, const char *all_keys, long long now_ts,
                     float retention);

// Frees a string returned by this library.
void mcat_string_free(char *s);

#endif /* MCAT_FFI_H */
