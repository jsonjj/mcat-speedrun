// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use anki_proto::mastery as pb;

use crate::collection::Collection;
use crate::error::Result;
use crate::mastery::Coverage;

impl crate::services::MasteryService for Collection {
    fn get_topic_mastery(
        &mut self,
        input: pb::GetTopicMasteryRequest,
    ) -> Result<pb::TopicMasteryResponse> {
        let report = self.compute_topic_mastery(&input.section)?;
        Ok(pb::TopicMasteryResponse {
            topics: report.topics.into_iter().map(topic_to_proto).collect(),
            total_graded_reviews: report.total_graded_reviews,
            total_performance_attempts: report.total_performance_attempts,
        })
    }

    fn mcat_scores(
        &mut self,
        input: pb::McatScoresRequest,
    ) -> Result<pb::McatScoresResponse> {
        let diagnostic_kind = if input.diagnostic_kind.is_empty() {
            None
        } else {
            Some(input.diagnostic_kind.as_str())
        };
        let scores_json = crate::mcat_core::api::scores_json(
            &input.state_json,
            &input.coverage_json,
            &input.external_json,
            diagnostic_kind,
        );
        Ok(pb::McatScoresResponse { scores_json })
    }

    fn mcat_merge(&mut self, input: pb::McatMergeRequest) -> Result<pb::McatMergeResponse> {
        let state_json = crate::mcat_core::api::merge_json(&input.state_json, &input.other_json);
        Ok(pb::McatMergeResponse { state_json })
    }

    fn mcat_due_cards(
        &mut self,
        input: pb::McatDueCardsRequest,
    ) -> Result<pb::McatDueCardsResponse> {
        let keys_json = crate::mcat_core::api::due_cards_json(
            &input.state_json,
            &input.all_keys_json,
            input.now_ts,
            input.retention,
        );
        Ok(pb::McatDueCardsResponse { keys_json })
    }
}

fn coverage_to_proto(coverage: Coverage) -> pb::CoverageStatus {
    match coverage {
        Coverage::None => pb::CoverageStatus::None,
        Coverage::MemoryOnly => pb::CoverageStatus::MemoryOnly,
        Coverage::PerformanceOnly => pb::CoverageStatus::PerformanceOnly,
        Coverage::Full => pb::CoverageStatus::Full,
    }
}

fn topic_to_proto(topic: crate::mastery::TopicMastery) -> pb::TopicMastery {
    let coverage = coverage_to_proto(topic.coverage()) as i32;
    pb::TopicMastery {
        topic_id: topic.topic_id,
        section: topic.section,
        total_cards: topic.total_cards,
        memory_cards: topic.memory_cards,
        performance_cards: topic.performance_cards,
        reviewed_cards: topic.reviewed_cards,
        due_cards: topic.due_cards,
        mature_cards: topic.mature_cards,
        graded_reviews: topic.graded_reviews,
        avg_retrievability: topic.avg_retrievability,
        performance_attempts: topic.performance_attempts,
        performance_first_correct: topic.performance_first_correct,
        calibration_certain: topic.calibration_certain,
        calibration_certain_correct: topic.calibration_certain_correct,
        calibration_guessing: topic.calibration_guessing,
        calibration_guessing_correct: topic.calibration_guessing_correct,
        coverage,
    }
}
