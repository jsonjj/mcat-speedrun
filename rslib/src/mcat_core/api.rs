// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! JSON string-in / string-out wrappers around the engine, so any host (iOS via
//! C FFI, desktop via the Python bridge) can drive the same code by passing
//! JSON. Keeping the boundary as plain strings avoids per-host binding churn.

use std::collections::HashMap;

use super::scoring::SectionCounts;
use super::McatState;
use super::DEFAULT_RETENTION;

/// Compute the three scores. `coverage_json` is `{ "bb": [covered, total], ... }`
/// and `external_json` is the other device's aggregate (or "" / "{}" for none).
pub fn scores_json(
    state_json: &str,
    coverage_json: &str,
    external_json: &str,
    diagnostic_kind: Option<&str>,
) -> String {
    let state = McatState::from_json(state_json);
    let coverage: HashMap<String, (usize, usize)> =
        serde_json::from_str(coverage_json).unwrap_or_default();
    let external: HashMap<String, SectionCounts> = if external_json.trim().is_empty() {
        HashMap::new()
    } else {
        serde_json::from_str(external_json).unwrap_or_default()
    };
    let scores = state.scores(&coverage, &external, diagnostic_kind);
    serde_json::to_string(&scores).unwrap_or_else(|_| "{}".to_string())
}

/// Replay-union merge of two states (used for appending local events and for
/// sync reconciliation). Returns the merged state JSON.
pub fn merge_json(state_json: &str, other_json: &str) -> String {
    let mut state = McatState::from_json(state_json);
    let other = McatState::from_json(other_json);
    state.merge(&other);
    state.to_json()
}

/// Card keys due now, given all known keys (`["k1","k2",...]`).
pub fn due_cards_json(
    state_json: &str,
    all_keys_json: &str,
    now_ts: i64,
    desired_retention: f32,
) -> String {
    let state = McatState::from_json(state_json);
    let all: Vec<String> = serde_json::from_str(all_keys_json).unwrap_or_default();
    let retention = if desired_retention > 0.0 {
        desired_retention
    } else {
        DEFAULT_RETENTION
    };
    let due = state.due_cards(&all, now_ts, retention);
    serde_json::to_string(&due).unwrap_or_else(|_| "[]".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scores_json_roundtrip() {
        let mut state = McatState::default();
        for batch in ["a", "b"] {
            for i in 0..10 {
                state.add_attempt(
                    format!("{batch}{i}"),
                    "bb",
                    format!("q{batch}{i}"),
                    1,
                    i < 7,
                    format!("bb-{batch}"),
                );
            }
        }
        let coverage = r#"{"bb":[7,10],"cp":[7,10],"ps":[7,10],"cars":[7,10]}"#;
        let out = scores_json(&state.to_json(), coverage, "", None);
        assert!(out.contains("percent_correct"));
        // 14/20 = 70% for bb performance; overall reflects only bb here.
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        let pt = v["performance"]["point"].as_f64().unwrap();
        assert!((pt - 70.0).abs() < 0.001);
    }

    #[test]
    fn merge_json_appends() {
        let a = McatState::default().to_json();
        let events = r#"{"reviews":[{"id":"r1","card_key":"c1","section":"bb","ts":1,"rating":3}],"attempts":[]}"#;
        let merged = merge_json(&a, events);
        let state = McatState::from_json(&merged);
        assert_eq!(state.reviews.len(), 1);
    }
}
