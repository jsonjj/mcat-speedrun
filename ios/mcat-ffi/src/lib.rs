// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! MCAT Speedrun iOS FFI.
//!
//! Thin C-ABI surface over the shared Anki/MCAT engine (`anki` / rslib) so the
//! SwiftUI app can call into Rust. This first function exists to prove the whole
//! engine cross-compiles and links for iOS; the real service surface (scoring,
//! planner, questions, etc.) is layered on top of this once the domain logic is
//! ported into Rust.

use std::ffi::CStr;
use std::ffi::CString;
use std::os::raw::c_char;

use anki::mcat_core::api;

/// Read a borrowed C string into an owned Rust `String` (empty when null).
///
/// # Safety
/// `ptr` must be null or a valid NUL-terminated C string.
unsafe fn read(ptr: *const c_char) -> String {
    if ptr.is_null() {
        String::new()
    } else {
        CStr::from_ptr(ptr).to_string_lossy().into_owned()
    }
}

/// Hand ownership of a heap C string to the caller (freed via `mcat_string_free`).
fn out(s: String) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

/// Returns the engine version string. Caller must free it with
/// [`mcat_string_free`]. Proves rslib links and runs on iOS.
///
/// # Safety
/// The returned pointer is owned by the caller until passed to
/// [`mcat_string_free`].
#[no_mangle]
pub extern "C" fn mcat_engine_version() -> *mut c_char {
    let v = anki::version::version();
    CString::new(v).unwrap_or_default().into_raw()
}

/// Compute the three scores. See the C header for the JSON argument shapes.
///
/// # Safety
/// All pointers must be null or valid C strings; the result must be freed with
/// [`mcat_string_free`].
#[no_mangle]
pub unsafe extern "C" fn mcat_scores(
    state: *const c_char,
    coverage: *const c_char,
    external: *const c_char,
    diag: *const c_char,
) -> *mut c_char {
    let diag = read(diag);
    let diag = if diag.is_empty() { None } else { Some(diag.as_str()) };
    out(api::scores_json(
        &read(state),
        &read(coverage),
        &read(external),
        diag,
    ))
}

/// Replay-union merge of two McatState JSON strings.
///
/// # Safety
/// Pointers must be null or valid C strings; free the result with
/// [`mcat_string_free`].
#[no_mangle]
pub unsafe extern "C" fn mcat_merge(
    state: *const c_char,
    other: *const c_char,
) -> *mut c_char {
    out(api::merge_json(&read(state), &read(other)))
}

/// Card keys due at `now_ts`. See the C header for argument shapes.
///
/// # Safety
/// Pointers must be null or valid C strings; free the result with
/// [`mcat_string_free`].
#[no_mangle]
pub unsafe extern "C" fn mcat_due_cards(
    state: *const c_char,
    all_keys: *const c_char,
    now_ts: i64,
    retention: f32,
) -> *mut c_char {
    out(api::due_cards_json(
        &read(state),
        &read(all_keys),
        now_ts,
        retention,
    ))
}

/// Frees a string previously returned by this library.
///
/// # Safety
/// `s` must be a pointer returned by this library and not already freed.
#[no_mangle]
pub unsafe extern "C" fn mcat_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}
