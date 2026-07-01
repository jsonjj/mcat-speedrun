// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! Shared MCAT engine.
//!
//! The single source of truth for MCAT study, used by BOTH the desktop (via the
//! Python bridge) and iOS (via the C FFI) so the two apps share one engine,
//! one FSRS scheduler and one scoring implementation.
//!
//! The state is two append-only event logs (memory reviews + performance
//! attempts). Everything else — per-card FSRS schedule and the three scores — is
//! *derived* by replaying those logs. That makes cross-device sync conflict-free:
//! merging is just the union of the logs by event id (replay-union), after which
//! both devices recompute identical state.

pub mod api;
pub mod scoring;

mod fsrs_sched;
#[cfg(test)]
mod tests;

use std::collections::HashMap;
use std::collections::HashSet;

use serde::Deserialize;
use serde::Serialize;

pub use fsrs_sched::CardSchedule;
pub use scoring::ScoreBlock;
pub use scoring::Scores;

/// Default desired retention for scheduling (matches Anki's FSRS default).
pub const DEFAULT_RETENTION: f32 = 0.9;

/// A single graded memory review. `section` is denormalised so scoring needs
/// only the log. `rating` is 1=Again, 2=Hard, 3=Good, 4=Easy.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReviewEvent {
    pub id: String,
    pub card_key: String,
    pub section: String,
    pub ts: i64,
    pub rating: u8,
}

/// A single first-pass performance answer.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttemptEvent {
    pub id: String,
    pub section: String,
    pub question_key: String,
    pub ts: i64,
    pub first_correct: bool,
    pub batch_id: String,
}

/// The synced state: two append-only logs. Derivations (schedule, scores) are
/// computed on demand.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct McatState {
    #[serde(default)]
    pub reviews: Vec<ReviewEvent>,
    #[serde(default)]
    pub attempts: Vec<AttemptEvent>,
}

impl McatState {
    pub fn from_json(json: &str) -> Self {
        serde_json::from_str(json).unwrap_or_default()
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| "{}".to_string())
    }

    /// Append a memory review. `id` must be globally unique (the platform mints a
    /// UUID) so the same event dedups correctly when merged across devices.
    pub fn add_review(
        &mut self,
        id: impl Into<String>,
        card_key: impl Into<String>,
        section: impl Into<String>,
        ts: i64,
        rating: u8,
    ) {
        self.reviews.push(ReviewEvent {
            id: id.into(),
            card_key: card_key.into(),
            section: section.into(),
            ts,
            rating: rating.clamp(1, 4),
        });
    }

    /// Append a first-pass performance answer.
    pub fn add_attempt(
        &mut self,
        id: impl Into<String>,
        section: impl Into<String>,
        question_key: impl Into<String>,
        ts: i64,
        first_correct: bool,
        batch_id: impl Into<String>,
    ) {
        self.attempts.push(AttemptEvent {
            id: id.into(),
            section: section.into(),
            question_key: question_key.into(),
            ts,
            first_correct,
            batch_id: batch_id.into(),
        });
    }

    /// Replay-union merge: fold in another device's logs, de-duplicating by event
    /// id and keeping both logs sorted by (ts, id) for a deterministic replay.
    pub fn merge(&mut self, other: &McatState) {
        let mut review_ids: HashSet<String> =
            self.reviews.iter().map(|r| r.id.clone()).collect();
        for r in &other.reviews {
            if review_ids.insert(r.id.clone()) {
                self.reviews.push(r.clone());
            }
        }
        let mut attempt_ids: HashSet<String> =
            self.attempts.iter().map(|a| a.id.clone()).collect();
        for a in &other.attempts {
            if attempt_ids.insert(a.id.clone()) {
                self.attempts.push(a.clone());
            }
        }
        self.reviews.sort_by(|a, b| (a.ts, &a.id).cmp(&(b.ts, &b.id)));
        self.attempts.sort_by(|a, b| (a.ts, &a.id).cmp(&(b.ts, &b.id)));
    }

    /// Per-card FSRS schedule, derived by replaying each card's reviews.
    pub fn card_schedules(&self, desired_retention: f32) -> HashMap<String, CardSchedule> {
        fsrs_sched::replay_all(&self.reviews, desired_retention)
    }

    /// Which of `all_card_keys` are due now: never reviewed, or past their due
    /// date. Callers pass the full card set (from the content pack) since new
    /// cards aren't in the review log yet.
    pub fn due_cards(
        &self,
        all_card_keys: &[String],
        now_ts: i64,
        desired_retention: f32,
    ) -> Vec<String> {
        let schedules = self.card_schedules(desired_retention);
        all_card_keys
            .iter()
            .filter(|key| match schedules.get(*key) {
                None => true,
                Some(s) => s.due_ts <= now_ts,
            })
            .cloned()
            .collect()
    }

    /// The three scores, computed from the logs + static topic coverage, with an
    /// optional `external` per-section aggregate folded in (the other device's
    /// study during the sync migration). This is the ONE scoring implementation
    /// both apps use.
    pub fn scores(
        &self,
        coverage: &HashMap<String, (usize, usize)>,
        external: &HashMap<String, scoring::SectionCounts>,
        diagnostic_kind: Option<&str>,
    ) -> Scores {
        scoring::compute(self, coverage, external, diagnostic_kind)
    }
}
