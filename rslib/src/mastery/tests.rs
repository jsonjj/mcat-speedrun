// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use super::Coverage;
use super::MasteryReport;
use super::TopicMastery;
use crate::prelude::*;

fn add_note_with_tags(col: &mut Collection, fields: &[&str], tags: &[&str]) -> Note {
    let nt = col.basic_notetype();
    let mut note = nt.new_note();
    *note.fields_mut() = fields.iter().map(ToString::to_string).collect();
    note.tags = tags.iter().map(ToString::to_string).collect();
    col.add_note(&mut note, DeckId(1)).unwrap();
    note
}

fn topic<'a>(report: &'a MasteryReport, topic_id: &str) -> &'a TopicMastery {
    report
        .topics
        .iter()
        .find(|t| t.topic_id == topic_id)
        .unwrap_or_else(|| panic!("topic {topic_id} not found"))
}

#[test]
fn coverage_distinguishes_memory_and_performance_items() {
    let mut col = Collection::new();
    // amino_acids has both a memory and a performance item -> full coverage.
    add_note_with_tags(
        &mut col,
        &["q1", "a1"],
        &[
            "exam:mcat",
            "section:bb",
            "topic:bb.amino_acids",
            "card_type:memory",
        ],
    );
    add_note_with_tags(
        &mut col,
        &["q2", "a2"],
        &[
            "exam:mcat",
            "section:bb",
            "topic:bb.amino_acids",
            "card_type:performance",
        ],
    );
    // enzymes has only a memory item -> memory-only coverage.
    add_note_with_tags(
        &mut col,
        &["q3", "a3"],
        &[
            "exam:mcat",
            "section:bb",
            "topic:bb.enzymes",
            "card_type:memory",
        ],
    );

    let report = col.compute_topic_mastery("").unwrap();

    let amino = topic(&report, "bb.amino_acids");
    assert_eq!(amino.coverage(), Coverage::Full);
    assert_eq!(amino.memory_cards, 1);
    assert_eq!(amino.performance_cards, 1);
    assert_eq!(amino.section, "bb");

    let enzymes = topic(&report, "bb.enzymes");
    assert_eq!(enzymes.coverage(), Coverage::MemoryOnly);
    assert_eq!(enzymes.memory_cards, 1);
    assert_eq!(enzymes.performance_cards, 0);
}

#[test]
fn section_filter_limits_results() {
    let mut col = Collection::new();
    add_note_with_tags(
        &mut col,
        &["q1", "a1"],
        &[
            "exam:mcat",
            "section:bb",
            "topic:bb.enzymes",
            "card_type:memory",
        ],
    );
    add_note_with_tags(
        &mut col,
        &["q2", "a2"],
        &[
            "exam:mcat",
            "section:cp",
            "topic:cp.fluids",
            "card_type:memory",
        ],
    );

    let all = col.compute_topic_mastery("").unwrap();
    assert_eq!(all.topics.len(), 2);

    let bb_only = col.compute_topic_mastery("bb").unwrap();
    assert_eq!(bb_only.topics.len(), 1);
    assert_eq!(bb_only.topics[0].topic_id, "bb.enzymes");
}

#[test]
fn performance_attempts_and_calibration_come_from_config() {
    let mut col = Collection::new();
    add_note_with_tags(
        &mut col,
        &["q1", "a1"],
        &[
            "exam:mcat",
            "section:bb",
            "topic:bb.enzymes",
            "card_type:performance",
        ],
    );

    let attempts = serde_json::json!([
        {
            "section": "bb",
            "topic_ids": ["bb.enzymes"],
            "first_correct": true,
            "confidence": "certain"
        },
        {
            "section": "bb",
            "topic_ids": ["bb.enzymes"],
            "first_correct": false,
            "confidence": "guessing"
        },
        {
            "section": "cp",
            "topic_ids": ["cp.fluids"],
            "first_correct": true,
            "confidence": "leaning"
        }
    ]);
    col.set_config_json("mcat:attempts", &attempts, false)
        .unwrap();

    let report = col.compute_topic_mastery("").unwrap();
    assert_eq!(report.total_performance_attempts, 3);

    let enzymes = topic(&report, "bb.enzymes");
    assert_eq!(enzymes.performance_attempts, 2);
    assert_eq!(enzymes.performance_first_correct, 1);
    assert_eq!(enzymes.calibration_certain, 1);
    assert_eq!(enzymes.calibration_certain_correct, 1);
    assert_eq!(enzymes.calibration_guessing, 1);
    assert_eq!(enzymes.calibration_guessing_correct, 0);

    // Section filter should also restrict attempt aggregation.
    let bb_only = col.compute_topic_mastery("bb").unwrap();
    assert_eq!(bb_only.total_performance_attempts, 2);
}

#[test]
fn reviewed_mature_and_retrievability_use_scheduling_state() {
    let mut col = Collection::new();
    let note = add_note_with_tags(
        &mut col,
        &["q1", "a1"],
        &[
            "exam:mcat",
            "section:bb",
            "topic:bb.metabolism",
            "card_type:memory",
        ],
    );
    let cids = col.storage.card_ids_of_notes(&[note.id]).unwrap();
    // Make the single card a reviewed, mature, not-overdue review card.
    col.storage
        .db
        .execute_batch(&format!(
            "UPDATE cards SET type = 2, queue = 2, ivl = 30, reps = 5, due = 1000000 WHERE id = {}",
            cids[0]
        ))
        .unwrap();

    let report = col.compute_topic_mastery("").unwrap();
    let metabolism = topic(&report, "bb.metabolism");
    assert_eq!(metabolism.reviewed_cards, 1);
    assert_eq!(metabolism.mature_cards, 1);
    assert_eq!(metabolism.graded_reviews, 5);
    assert_eq!(report.total_graded_reviews, 5);
    // Not overdue -> recall proxy is ~1.0.
    assert!((metabolism.avg_retrievability - 1.0).abs() < 1e-9);
}
