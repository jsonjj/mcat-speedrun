// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! MCAT Speedrun: the Mastery Query.
//!
//! Aggregates per-topic mastery from the collection so dashboards can show
//! memory/performance/coverage without N+1 round-trips from Python. The memory
//! side comes from cards + their scheduling state (read by topic tag); the
//! performance side comes from the MCAT attempts stored in the collection
//! config (`mcat:attempts`). Topics are discovered from `topic:<id>` tags, so
//! this stays agnostic of the (Python-owned) taxonomy.
//!
//! See docs/mcat-mastery-query-note.md for why this lives in Rust.

mod service;

use std::collections::HashMap;

use serde::Deserialize;

use crate::card::CardQueue;
use crate::card::CardType;
use crate::prelude::*;
use crate::search::SearchNode;
use crate::search::SortMode;

/// A card is considered "mature" once its interval reaches this many days.
const MATURE_INTERVAL_DAYS: u32 = 21;

const TAG_EXAM_MCAT: &str = "exam:mcat";
const TAG_TOPIC_PREFIX: &str = "topic:";
const TAG_SECTION_PREFIX: &str = "section:";
const TAG_CARD_TYPE_PREFIX: &str = "card_type:";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Coverage {
    None,
    MemoryOnly,
    PerformanceOnly,
    Full,
}

#[derive(Debug, Clone, Default)]
pub struct TopicMastery {
    pub topic_id: String,
    pub section: String,
    pub total_cards: u32,
    pub memory_cards: u32,
    pub performance_cards: u32,
    pub reviewed_cards: u32,
    pub due_cards: u32,
    pub mature_cards: u32,
    pub graded_reviews: u32,
    pub avg_retrievability: f64,
    pub performance_attempts: u32,
    pub performance_first_correct: u32,
    pub calibration_certain: u32,
    pub calibration_certain_correct: u32,
    pub calibration_guessing: u32,
    pub calibration_guessing_correct: u32,
}

impl TopicMastery {
    pub fn coverage(&self) -> Coverage {
        match (self.memory_cards > 0, self.performance_cards > 0) {
            (true, true) => Coverage::Full,
            (true, false) => Coverage::MemoryOnly,
            (false, true) => Coverage::PerformanceOnly,
            (false, false) => Coverage::None,
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct MasteryReport {
    pub topics: Vec<TopicMastery>,
    pub total_graded_reviews: u32,
    pub total_performance_attempts: u32,
}

/// Subset of a stored `mcat:attempts` record needed for aggregation.
#[derive(Debug, Default, Deserialize)]
struct AttemptRecord {
    #[serde(default)]
    section: String,
    #[serde(default)]
    topic_ids: Vec<String>,
    #[serde(default)]
    first_correct: bool,
    #[serde(default)]
    confidence: String,
}

#[derive(Default)]
struct TopicAcc {
    section: String,
    total_cards: u32,
    memory_cards: u32,
    performance_cards: u32,
    reviewed_cards: u32,
    due_cards: u32,
    mature_cards: u32,
    graded_reviews: u32,
    retr_sum: f64,
    retr_count: u32,
    performance_attempts: u32,
    performance_first_correct: u32,
    calibration_certain: u32,
    calibration_certain_correct: u32,
    calibration_guessing: u32,
    calibration_guessing_correct: u32,
}

fn tag_value<'a>(tags: &'a [String], prefix: &str) -> Option<&'a str> {
    tags.iter()
        .find_map(|t| t.strip_prefix(prefix))
        .filter(|v| !v.is_empty())
}

fn topic_ids(tags: &[String]) -> Vec<String> {
    tags.iter()
        .filter_map(|t| t.strip_prefix(TAG_TOPIC_PREFIX))
        .filter(|v| !v.is_empty())
        .map(str::to_string)
        .collect()
}

impl Collection {
    /// Compute per-topic mastery, optionally limited to one MCAT section.
    pub fn compute_topic_mastery(&mut self, section_filter: &str) -> Result<MasteryReport> {
        let today = self.timing_today()?.days_elapsed as i32;

        // All MCAT cards in one query; we read each card's note tags to bucket.
        let card_ids =
            self.search_cards(SearchNode::from_tag_name(TAG_EXAM_MCAT), SortMode::NoOrder)?;

        let mut acc: HashMap<String, TopicAcc> = HashMap::new();
        let mut note_tag_cache: HashMap<NoteId, Vec<String>> = HashMap::new();
        let mut total_graded_reviews: u32 = 0;

        for cid in card_ids {
            let card = match self.storage.get_card(cid)? {
                Some(c) => c,
                None => continue,
            };
            let tags = match note_tag_cache.get(&card.note_id) {
                Some(t) => t.clone(),
                None => {
                    let note = match self.storage.get_note(card.note_id)? {
                        Some(n) => n,
                        None => continue,
                    };
                    note_tag_cache.insert(card.note_id, note.tags.clone());
                    note.tags
                }
            };

            let section = tag_value(&tags, TAG_SECTION_PREFIX)
                .unwrap_or("")
                .to_string();
            if !section_filter.is_empty() && section != section_filter {
                continue;
            }
            let is_memory = tag_value(&tags, TAG_CARD_TYPE_PREFIX) == Some("memory");
            let is_review_queue = matches!(card.queue, CardQueue::Review);
            let reviewed = card.reps > 0;
            let mature =
                matches!(card.ctype, CardType::Review) && card.interval >= MATURE_INTERVAL_DAYS;
            let due = is_review_queue && card.due <= today;
            let retrievability = recall_proxy(today, card.due, card.interval, is_review_queue);

            if is_memory {
                total_graded_reviews = total_graded_reviews.saturating_add(card.reps);
            }

            for topic_id in topic_ids(&tags) {
                let entry = acc.entry(topic_id).or_default();
                if entry.section.is_empty() {
                    entry.section = section.clone();
                }
                entry.total_cards += 1;
                if is_memory {
                    entry.memory_cards += 1;
                    entry.graded_reviews = entry.graded_reviews.saturating_add(card.reps);
                } else {
                    entry.performance_cards += 1;
                }
                if reviewed {
                    entry.reviewed_cards += 1;
                }
                if due {
                    entry.due_cards += 1;
                }
                if mature {
                    entry.mature_cards += 1;
                }
                if is_memory && reviewed && is_review_queue {
                    entry.retr_sum += retrievability;
                    entry.retr_count += 1;
                }
            }
        }

        // Performance attempts from the synced config.
        let attempts: Vec<AttemptRecord> = self
            .get_config_optional::<Vec<AttemptRecord>, &str>("mcat:attempts")
            .unwrap_or_default();
        let mut total_performance_attempts: u32 = 0;
        for attempt in &attempts {
            if !section_filter.is_empty() && attempt.section != section_filter {
                continue;
            }
            total_performance_attempts += 1;
            let certain = attempt.confidence == "certain";
            let guessing = attempt.confidence == "guessing";
            for topic_id in &attempt.topic_ids {
                let entry = acc.entry(topic_id.clone()).or_default();
                if entry.section.is_empty() {
                    entry.section = attempt.section.clone();
                }
                entry.performance_attempts += 1;
                if attempt.first_correct {
                    entry.performance_first_correct += 1;
                }
                if certain {
                    entry.calibration_certain += 1;
                    if attempt.first_correct {
                        entry.calibration_certain_correct += 1;
                    }
                } else if guessing {
                    entry.calibration_guessing += 1;
                    if attempt.first_correct {
                        entry.calibration_guessing_correct += 1;
                    }
                }
            }
        }

        let mut topics: Vec<TopicMastery> = acc
            .into_iter()
            .map(|(topic_id, a)| TopicMastery {
                topic_id,
                section: a.section,
                total_cards: a.total_cards,
                memory_cards: a.memory_cards,
                performance_cards: a.performance_cards,
                reviewed_cards: a.reviewed_cards,
                due_cards: a.due_cards,
                mature_cards: a.mature_cards,
                graded_reviews: a.graded_reviews,
                avg_retrievability: if a.retr_count > 0 {
                    a.retr_sum / a.retr_count as f64
                } else {
                    0.0
                },
                performance_attempts: a.performance_attempts,
                performance_first_correct: a.performance_first_correct,
                calibration_certain: a.calibration_certain,
                calibration_certain_correct: a.calibration_certain_correct,
                calibration_guessing: a.calibration_guessing,
                calibration_guessing_correct: a.calibration_guessing_correct,
            })
            .collect();
        topics.sort_by(|a, b| a.topic_id.cmp(&b.topic_id));

        Ok(MasteryReport {
            topics,
            total_graded_reviews,
            total_performance_attempts,
        })
    }
}

/// A bounded recall proxy in [0, 1] based on real scheduling data. Cards that
/// are not overdue read ~1.0; recall decays as a card becomes overdue relative
/// to its interval. (FSRS memory state can refine this later.)
fn recall_proxy(today: i32, due: i32, interval: u32, is_review_queue: bool) -> f64 {
    if !is_review_queue {
        return 0.0;
    }
    let overdue = (today - due).max(0) as f64;
    let ivl = (interval.max(1)) as f64;
    (-overdue / ivl).exp().clamp(0.0, 1.0)
}

#[cfg(test)]
mod tests;
