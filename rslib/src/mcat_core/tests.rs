// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use std::collections::HashMap;

use super::scoring::SectionCounts;
use super::McatState;
use super::DEFAULT_RETENTION;

fn no_external() -> HashMap<String, SectionCounts> {
    HashMap::new()
}

fn round_half_up(x: f64) -> i64 {
    (x + 0.5).floor() as i64
}

/// The canonical reference scenario, matching the Python parity test
/// (`pylib/tests/test_mcat.py`): 2 performance sets/section and 30 memory
/// reviews/section, with known correct counts.
fn reference_state() -> McatState {
    let mut state = McatState::default();
    // (section, perf-correct-per-set-of-10, memory-correct-of-30)
    let plan = [("bb", 7, 24), ("cp", 6, 20), ("ps", 5, 18), ("cars", 8, 26)];
    let mut id = 0;
    for (section, correct, mem_correct) in plan {
        for batch in ["a", "b"] {
            for i in 0..10 {
                id += 1;
                state.add_attempt(
                    format!("att{id}"),
                    section,
                    format!("{section}-q{batch}{i}"),
                    1000,
                    i < correct,
                    format!("{section}-{batch}"),
                );
            }
        }
        for i in 0..30 {
            id += 1;
            let rating = if i < mem_correct { 3 } else { 1 };
            state.add_review(
                format!("rev{id}"),
                format!("{section}-c{i}"),
                section,
                1000 + i as i64,
                rating,
            );
        }
    }
    state
}

fn uniform_coverage() -> HashMap<String, (usize, usize)> {
    let mut c = HashMap::new();
    for s in ["bb", "cp", "ps", "cars"] {
        c.insert(s.to_string(), (7usize, 10usize)); // 0.70, above the 0.40 gate
    }
    c
}

#[test]
fn scores_match_the_reference_values() {
    let state = reference_state();
    let scores = state.scores(&uniform_coverage(), &no_external(), None);

    // Overall (displayed values round half-up on both platforms).
    assert_eq!(round_half_up(scores.memory.point.unwrap()), 73);
    assert_eq!(round_half_up(scores.performance.point.unwrap()), 65);
    assert!(!scores.readiness.abstained);
    assert_eq!(scores.readiness.point.unwrap() as i64, 507);
    assert_eq!(scores.readiness.low.unwrap() as i64, 495);
    assert_eq!(scores.readiness.high.unwrap() as i64, 518);
    assert_eq!((scores.est_low, scores.est_high), (495, 518));

    // Per-section readiness.
    let expected = [
        ("bb", 128, 124, 130),
        ("cp", 126, 123, 129),
        ("ps", 124, 122, 128),
        ("cars", 129, 126, 131),
    ];
    for (code, pt, lo, hi) in expected {
        let r = &scores.sections[code].readiness;
        assert_eq!(
            (
                r.point.unwrap() as i64,
                r.low.unwrap() as i64,
                r.high.unwrap() as i64
            ),
            (pt, lo, hi),
            "section {code}"
        );
    }
}

#[test]
fn readiness_abstains_without_enough_evidence() {
    let mut state = McatState::default();
    state.add_attempt("a1", "bb", "q1", 1000, true, "b1");
    let scores = state.scores(&uniform_coverage(), &no_external(), None);
    assert!(scores.readiness.abstained);
    assert!(scores.sections["cp"].performance.abstained);
}

#[test]
fn diagnostic_exception_shows_low_confidence_range() {
    // One set/section (sets=1 < 2) so the strict gate fails, but a standard
    // diagnostic unlocks a low-confidence estimate.
    let mut state = McatState::default();
    let mut id = 0;
    for (section, correct) in [("bb", 7), ("cp", 6), ("ps", 5), ("cars", 8)] {
        for i in 0..10 {
            id += 1;
            state.add_attempt(
                format!("d{id}"),
                section,
                format!("{section}-q{i}"),
                1000,
                i < correct,
                format!("{section}-diag"),
            );
        }
    }
    let scores = state.scores(&uniform_coverage(), &no_external(), Some("standard"));
    assert!(!scores.readiness.abstained);
    assert!(scores.est_low >= 472 && scores.est_high <= 528);
    assert!(scores.est_low <= scores.est_high);
}

#[test]
fn external_aggregate_folds_into_scores() {
    // Local has only bb (14/20); the external (other device) supplies the rest.
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
    let mut external = HashMap::new();
    external.insert(
        "cp".to_string(),
        SectionCounts { attempts: 20, correct: 12, sets: 2, ..Default::default() },
    );
    external.insert(
        "ps".to_string(),
        SectionCounts { attempts: 20, correct: 10, sets: 2, ..Default::default() },
    );
    external.insert(
        "cars".to_string(),
        SectionCounts { attempts: 20, correct: 16, sets: 2, ..Default::default() },
    );
    let scores = state.scores(&uniform_coverage(), &external, None);
    // 14 + 12 + 10 + 16 = 52 of 80 = 65%.
    assert_eq!(round_half_up(scores.performance.point.unwrap()), 65);
}

#[test]
fn merge_is_union_by_event_id() {
    let mut a = McatState::default();
    a.add_review("r1", "bb-c1", "bb", 100, 3);
    a.add_review("r2", "bb-c2", "bb", 200, 3);

    let mut b = McatState::default();
    b.add_review("r2", "bb-c2", "bb", 200, 3); // duplicate id
    b.add_review("r3", "bb-c3", "bb", 150, 1); // new, earlier ts

    a.merge(&b);
    assert_eq!(a.reviews.len(), 3);
    // Sorted by (ts, id): r1(100), r3(150), r2(200).
    let ids: Vec<&str> = a.reviews.iter().map(|r| r.id.as_str()).collect();
    assert_eq!(ids, ["r1", "r3", "r2"]);
}

#[test]
fn review_syncs_and_reschedules_across_devices() {
    // Device A reviews a card (Good). Device B is fresh, then merges A's log.
    let now = 1_000_000i64;
    let mut a = McatState::default();
    a.add_review("r1", "card1", "bb", now, 3);

    let mut b = McatState::default();
    b.merge(&a);

    // On B, the card reviewed on A is now scheduled ahead (not due); a card that
    // was never reviewed anywhere is still due. This is the per-card sync.
    let all = vec!["card1".to_string(), "card2".to_string()];
    let due = b.due_cards(&all, now, DEFAULT_RETENTION);
    assert!(!due.contains(&"card1".to_string()));
    assert!(due.contains(&"card2".to_string()));
}

#[test]
fn fsrs_schedule_advances_due_date() {
    let mut state = McatState::default();
    let day = 86_400i64;
    // Three Good reviews spaced a few days apart.
    state.add_review("v1", "card", "bb", 0, 3);
    state.add_review("v2", "card", "bb", 3 * day, 3);
    state.add_review("v3", "card", "bb", 10 * day, 3);

    let schedules = state.card_schedules(DEFAULT_RETENTION);
    let card = schedules.get("card").expect("scheduled");
    assert_eq!(card.reps, 3);
    assert!(card.stability > 0.0);
    // After the last review the card is scheduled into the future.
    assert!(card.due_ts > 10 * day);

    // A brand-new card (never reviewed) is due; the reviewed one is not (yet).
    let all = vec!["card".to_string(), "fresh".to_string()];
    let due = state.due_cards(&all, 10 * day, DEFAULT_RETENTION);
    assert!(due.contains(&"fresh".to_string()));
    assert!(!due.contains(&"card".to_string()));
}
