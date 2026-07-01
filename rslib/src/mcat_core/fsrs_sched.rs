// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! FSRS scheduling for MCAT memory cards. Per-card state (stability, difficulty,
//! due date) is derived by replaying that card's reviews through FSRS — the same
//! engine the desktop uses — so scheduling is identical wherever it runs.

use std::collections::HashMap;

use fsrs::MemoryState;
use fsrs::DEFAULT_PARAMETERS;
use fsrs::FSRS;
use serde::Serialize;

use super::ReviewEvent;

const SECS_PER_DAY: i64 = 86_400;

/// Derived FSRS schedule for one card.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct CardSchedule {
    pub card_key: String,
    pub stability: f32,
    pub difficulty: f32,
    pub due_ts: i64,
    pub reps: u32,
}

/// Replay every card's reviews to get its current schedule.
pub fn replay_all(
    reviews: &[ReviewEvent],
    desired_retention: f32,
) -> HashMap<String, CardSchedule> {
    let mut by_card: HashMap<&str, Vec<&ReviewEvent>> = HashMap::new();
    for r in reviews {
        by_card.entry(r.card_key.as_str()).or_default().push(r);
    }
    let fsrs = match FSRS::new(Some(&DEFAULT_PARAMETERS[..])) {
        Ok(f) => f,
        Err(_) => return HashMap::new(),
    };
    let mut out = HashMap::new();
    for (key, mut events) in by_card {
        events.sort_by(|a, b| (a.ts, &a.id).cmp(&(b.ts, &b.id)));
        if let Some(schedule) = replay_card(&fsrs, &events, desired_retention) {
            out.insert(key.to_string(), schedule);
        }
    }
    out
}

fn replay_card(
    fsrs: &FSRS,
    events: &[&ReviewEvent],
    desired_retention: f32,
) -> Option<CardSchedule> {
    let first = events.first()?;
    let mut state: Option<MemoryState> = None;
    let mut prev_ts = first.ts;
    let mut due_ts = first.ts;

    for (i, event) in events.iter().enumerate() {
        let days_elapsed = if i == 0 {
            0
        } else {
            ((event.ts - prev_ts).max(0) / SECS_PER_DAY) as u32
        };
        let next = match fsrs.next_states(state, desired_retention, days_elapsed) {
            Ok(n) => n,
            Err(_) => break,
        };
        let chosen = match event.rating {
            1 => next.again,
            2 => next.hard,
            3 => next.good,
            _ => next.easy,
        };
        state = Some(chosen.memory);
        let interval_days = chosen.interval.max(1.0).round() as i64;
        due_ts = event.ts + interval_days * SECS_PER_DAY;
        prev_ts = event.ts;
    }

    let memory = state.unwrap_or(MemoryState {
        stability: 0.0,
        difficulty: 0.0,
    });
    Some(CardSchedule {
        card_key: first.card_key.clone(),
        stability: memory.stability,
        difficulty: memory.difficulty,
        due_ts,
        reps: events.len() as u32,
    })
}
