// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! The ONE MCAT scoring implementation, shared by desktop and iOS. A pure
//! function of the study logs + static topic coverage, so both apps display
//! byte-identical numbers. Mirrors the transparent, AI-off model: Memory =
//! recall accuracy, Performance = Wilson interval, Readiness = performance mapped
//! onto 118-132 (summed), with strict abstention or a low-confidence diagnostic
//! estimate.

use std::collections::BTreeMap;
use std::collections::HashMap;
use std::collections::HashSet;

use serde::Deserialize;
use serde::Serialize;

use super::McatState;

/// Per-section study counts. Used both internally and as the shape of an
/// "external" aggregate folded in from another device during the sync migration.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct SectionCounts {
    #[serde(default)]
    pub attempts: usize,
    #[serde(default)]
    pub correct: usize,
    #[serde(default)]
    pub sets: usize,
    #[serde(default)]
    pub reviews: usize,
    #[serde(default, rename = "reviewsCorrect", alias = "reviews_correct")]
    pub reviews_correct: usize,
}

pub const SECTIONS: [&str; 4] = ["bb", "cp", "ps", "cars"];

const SECTION_COVERAGE_MIN: f64 = 0.40;
const MIN_PERF_SETS: usize = 2;
const OVERALL_MIN_REVIEWS: usize = 100;
const OVERALL_MIN_ATTEMPTS: usize = 40;
const TOTAL_MIN: i32 = 472;
const TOTAL_MAX: i32 = 528;

/// A single score with an optional range. `point/low/high` are raw values; the
/// UI rounds half-up for display (identical on both platforms).
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct ScoreBlock {
    pub abstained: bool,
    pub point: Option<f64>,
    pub low: Option<f64>,
    pub high: Option<f64>,
    pub unit: String,
    pub coverage_pct: f64,
}

impl ScoreBlock {
    fn abstained(unit: &str, coverage_pct: f64) -> Self {
        Self {
            abstained: true,
            point: None,
            low: None,
            high: None,
            unit: unit.to_string(),
            coverage_pct,
        }
    }

    fn new(unit: &str, point: f64, low: f64, high: f64, coverage_pct: f64) -> Self {
        Self {
            abstained: false,
            point: Some(point),
            low: Some(low),
            high: Some(high),
            unit: unit.to_string(),
            coverage_pct,
        }
    }
}

#[derive(Clone, Debug, Serialize)]
pub struct SectionScores {
    pub coverage_pct: f64,
    pub memory: ScoreBlock,
    pub performance: ScoreBlock,
    pub readiness: ScoreBlock,
}

#[derive(Clone, Debug, Serialize)]
pub struct Scores {
    pub memory: ScoreBlock,
    pub performance: ScoreBlock,
    pub readiness: ScoreBlock,
    pub sections: BTreeMap<String, SectionScores>,
    pub est_low: i32,
    pub est_high: i32,
}

fn aggregate(
    state: &McatState,
    external: &HashMap<String, SectionCounts>,
) -> HashMap<String, SectionCounts> {
    let mut sets: HashMap<String, HashSet<String>> = HashMap::new();
    let mut out: HashMap<String, SectionCounts> = HashMap::new();
    for a in &state.attempts {
        let e = out.entry(a.section.clone()).or_default();
        e.attempts += 1;
        if a.first_correct {
            e.correct += 1;
        }
        if !a.batch_id.is_empty() {
            sets.entry(a.section.clone())
                .or_default()
                .insert(a.batch_id.clone());
        }
    }
    for r in &state.reviews {
        let e = out.entry(r.section.clone()).or_default();
        e.reviews += 1;
        if r.rating >= 3 {
            e.reviews_correct += 1;
        }
    }
    for (section, ids) in sets {
        out.entry(section).or_default().sets = ids.len();
    }
    // Fold in the other device's aggregate so scores reflect combined study.
    for (section, ext) in external {
        let e = out.entry(section.clone()).or_default();
        e.attempts += ext.attempts;
        e.correct += ext.correct;
        e.sets += ext.sets;
        e.reviews += ext.reviews;
        e.reviews_correct += ext.reviews_correct;
    }
    out
}

pub fn compute(
    state: &McatState,
    coverage: &HashMap<String, (usize, usize)>,
    external: &HashMap<String, SectionCounts>,
    diagnostic_kind: Option<&str>,
) -> Scores {
    let aggs = aggregate(state, external);

    let mut sections: BTreeMap<String, SectionScores> = BTreeMap::new();
    let mut mem_points: Vec<f64> = Vec::new();
    let mut perf_props: Vec<Option<(f64, f64, f64)>> = Vec::new();
    let mut section_readiness: Vec<ScoreBlock> = Vec::new();
    let mut total_attempts = 0usize;
    let mut total_correct = 0usize;
    let mut total_reviews = 0usize;
    let mut ready_count = 0usize;
    let mut coverage_sum = 0.0f64;

    let default_agg = SectionCounts::default();
    for section in SECTIONS {
        let a = aggs.get(section).unwrap_or(&default_agg);
        let (covered, total) = coverage.get(section).copied().unwrap_or((0, 1));
        let total = total.max(1);
        let cov_pct = covered as f64 / total as f64;
        coverage_sum += cov_pct;
        total_attempts += a.attempts;
        total_correct += a.correct;
        total_reviews += a.reviews;

        // Memory: recall accuracy.
        let mem_block = if a.reviews > 0 {
            let point = a.reviews_correct as f64 / a.reviews as f64 * 100.0;
            mem_points.push(point);
            let band = if a.reviews < 20 {
                18.0
            } else if a.reviews < 80 {
                10.0
            } else {
                5.0
            };
            ScoreBlock::new(
                "percent_recall",
                point,
                (point - band).max(0.0),
                (point + band).min(100.0),
                cov_pct,
            )
        } else {
            ScoreBlock::abstained("percent_recall", cov_pct)
        };

        // Performance: Wilson interval.
        let perf = if a.attempts > 0 {
            Some(wilson(a.correct, a.attempts))
        } else {
            None
        };
        let perf_block = match perf {
            Some((p, lo, hi)) => ScoreBlock::new(
                "percent_correct",
                p * 100.0,
                lo * 100.0,
                hi * 100.0,
                cov_pct,
            ),
            None => ScoreBlock::abstained("percent_correct", cov_pct),
        };

        // Section readiness.
        let readiness = match perf {
            Some((p, lo, hi))
                if cov_pct >= SECTION_COVERAGE_MIN && a.sets >= MIN_PERF_SETS =>
            {
                ready_count += 1;
                ScoreBlock::new(
                    "section_score",
                    section_score_int(p) as f64,
                    section_score_int(lo) as f64,
                    section_score_int(hi) as f64,
                    cov_pct,
                )
            }
            _ => ScoreBlock::abstained("section_score", cov_pct),
        };

        perf_props.push(perf);
        section_readiness.push(readiness.clone());
        sections.insert(
            section.to_string(),
            SectionScores {
                coverage_pct: cov_pct,
                memory: mem_block,
                performance: perf_block,
                readiness,
            },
        );
    }

    let coverage_overall = coverage_sum / SECTIONS.len() as f64;

    let memory = if mem_points.is_empty() {
        ScoreBlock::abstained("percent_recall", coverage_overall)
    } else {
        let avg = mem_points.iter().sum::<f64>() / mem_points.len() as f64;
        ScoreBlock::new(
            "percent_recall",
            avg,
            (avg - 8.0).max(0.0),
            (avg + 8.0).min(100.0),
            coverage_overall,
        )
    };

    let performance = if total_attempts > 0 {
        let (p, lo, hi) = wilson(total_correct, total_attempts);
        ScoreBlock::new(
            "percent_correct",
            p * 100.0,
            lo * 100.0,
            hi * 100.0,
            coverage_overall,
        )
    } else {
        ScoreBlock::abstained("percent_correct", coverage_overall)
    };

    let all_ready = ready_count == SECTIONS.len();
    let all_represented = perf_props.iter().all(|p| p.is_some());
    let (readiness, est_low, est_high) = if all_ready
        && total_reviews >= OVERALL_MIN_REVIEWS
        && total_attempts >= OVERALL_MIN_ATTEMPTS
    {
        let lo: f64 = section_readiness.iter().filter_map(|r| r.low).sum();
        let hi: f64 = section_readiness.iter().filter_map(|r| r.high).sum();
        let pt: f64 = section_readiness.iter().filter_map(|r| r.point).sum();
        (
            ScoreBlock::new("mcat_total", pt, lo, hi, coverage_overall),
            lo as i32,
            hi as i32,
        )
    } else if matches!(diagnostic_kind, Some("standard") | Some("best_estimate"))
        && all_represented
    {
        let mut lo = 0i32;
        let mut hi = 0i32;
        let mut pt = 0i32;
        for &(pp, plo, phi) in perf_props.iter().flatten() {
            lo += section_score_int(plo) - 1;
            hi += section_score_int(phi) + 1;
            pt += section_score_int(pp);
        }
        let lo = lo.max(TOTAL_MIN);
        let hi = hi.min(TOTAL_MAX);
        (
            ScoreBlock::new("mcat_total", pt as f64, lo as f64, hi as f64, coverage_overall),
            lo,
            hi,
        )
    } else {
        (ScoreBlock::abstained("mcat_total", coverage_overall), 0, 0)
    };

    Scores {
        memory,
        performance,
        readiness,
        sections,
        est_low,
        est_high,
    }
}

// Math (identical to the Python/Swift ports).

fn round_half_up(x: f64) -> i32 {
    (x + 0.5).floor() as i32
}

fn wilson(successes: usize, n: usize) -> (f64, f64, f64) {
    if n == 0 {
        return (0.0, 0.0, 1.0);
    }
    let z = 1.96f64;
    let nn = n as f64;
    let phat = successes as f64 / nn;
    let denom = 1.0 + z * z / nn;
    let center = (phat + z * z / (2.0 * nn)) / denom;
    let margin = (z * (phat * (1.0 - phat) / nn + z * z / (4.0 * nn * nn)).sqrt()) / denom;
    (phat, (center - margin).max(0.0), (center + margin).min(1.0))
}

const ANCHORS: [(f64, f64); 10] = [
    (0.00, 118.0),
    (0.25, 121.0),
    (0.40, 123.0),
    (0.50, 124.0),
    (0.55, 125.0),
    (0.65, 127.0),
    (0.75, 128.0),
    (0.85, 130.0),
    (0.92, 131.0),
    (1.00, 132.0),
];

fn to_section_score(proportion: f64) -> f64 {
    let p = proportion.clamp(0.0, 1.0);
    for i in 1..ANCHORS.len() {
        let (x0, y0) = ANCHORS[i - 1];
        let (x1, y1) = ANCHORS[i];
        if p <= x1 {
            if x1 == x0 {
                return y1;
            }
            let t = (p - x0) / (x1 - x0);
            return y0 + t * (y1 - y0);
        }
    }
    ANCHORS[ANCHORS.len() - 1].1
}

fn section_score_int(proportion: f64) -> i32 {
    round_half_up(to_section_score(proportion))
}
