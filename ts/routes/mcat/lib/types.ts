// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

export interface ScoreBlock {
    abstained: boolean;
    abstention_reason: string | null;
    point: number | null;
    low: number | null;
    high: number | null;
    unit: string | null;
    confidence: string | null;
    coverage_pct: number;
    evidence: string;
    missing: string | null;
    best_next_action: string;
    count?: number | null;
    count_unit?: string | null;
    updated_at: number;
}

export interface SectionScores {
    name: string;
    coverage_pct: number;
    covered_topics: number;
    total_topics: number;
    memory: ScoreBlock;
    performance: ScoreBlock;
    readiness: ScoreBlock;
}

export interface Scores {
    generated_at: number;
    ai_enabled: boolean;
    memory: ScoreBlock;
    performance: ScoreBlock;
    readiness: ScoreBlock;
    sections: Record<string, SectionScores>;
}

export interface Profile {
    name: string | null;
    email: string | null;
    exam_date: string | null;
    start_date: string | null;
    daily_minutes: number;
    onboarding_done: boolean;
    diagnostic_done: boolean;
    diagnostic_kind: string | null;
    last_diagnostic_date: string | null;
    logged_in: boolean;
    is_dev: boolean;
    ai_enabled: boolean;
}

export interface Streak {
    count: number;
    last_completed_date: string | null;
}

export interface DashboardData {
    has_content: boolean;
    profile: Profile;
    streak: Streak;
    scores: Scores | null;
    free_practice_unlocked?: boolean;
    roadmap?: { done: number; total: number };
}

export interface Choice {
    key: string;
    text: string;
}

export interface Question {
    note_id: number;
    question: string;
    choices: Choice[];
    section: string;
    topic_ids: string[];
    difficulty: number;
    source_id: string;
}

export interface QuestionBatch {
    batch_id: string;
    phase?: string;
    kind?: string;
    questions: Question[];
}

export interface AiFeedback {
    verdict: string;
    feedback: string;
    key_point: string;
    source: string;
}

export interface CoachRecommendation {
    focus: string;
    section: string;
    headline: string;
    detail: string;
    source: string;
}

export interface CoachResponse {
    ai_enabled: boolean;
    recommendation: CoachRecommendation | null;
}

export interface RevealResult {
    note_id: number;
    correct: string;
    explanation: string;
    first_correct: boolean;
    second_correct?: boolean;
    label?: string | null;
    ai_feedback?: AiFeedback;
}

export interface FirstPassResponse {
    reveal: boolean;
    batch_id: string;
    wrong_count: number;
    total: number;
    message?: string;
    results?: RevealResult[];
}

export interface BlockScore {
    correct: number;
    total: number;
}

export interface RoadmapBlock {
    id: string;
    kind: string;
    section: string | null;
    mode: string;
    label: string;
    minutes: number;
    required: boolean;
    completed: boolean;
    score?: BlockScore | null;
    meta: Record<string, unknown>;
}

// Grounded reason the current roadmap block was picked (from measured scores).
export interface WhyThis {
    title: string;
    metric: string;
    current_pct: number | null;
    target_pct: number | null;
    fact: string | null;
}

export interface FullLengthGuidance {
    phase: string;
    cadence: string;
    recommendation: string;
}

export interface Roadmap {
    date: string;
    exam_date: string | null;
    days_until_exam: number | null;
    phase?: string;
    phase_label?: string;
    daily_minutes: number;
    target_minutes: number;
    planned_minutes: number;
    primary_section: string;
    secondary_section: string;
    near_exam: boolean;
    full_length: FullLengthGuidance;
    blocks: RoadmapBlock[];
}

export interface RoadmapResponse {
    plan: Roadmap;
    streak: Streak;
    free_practice_unlocked: boolean;
    is_dev: boolean;
    why?: WhyThis | null;
}

export interface AccountStats {
    reps: number;
    sets: number;
    attempts: number;
    debates: number;
    studied_hours: number;
    reps_this_week: number;
    attempts_this_week: number;
    sets_this_week: number;
}

export interface AccountTrend {
    recall: number[];
    applied: number[];
    recall_delta: number;
    applied_delta: number;
}

export interface AccountData {
    profile: Profile;
    streak: Streak;
    scores: Scores | null;
    stats?: AccountStats;
    trend?: AccountTrend;
}

export interface CarsPassage {
    note_id: number;
    passage: string;
    author_claim: string;
    prompts: string[];
    skill_type: string;
    strong_rebuttal: string;
    strong_defense: string;
    prompt_skills: string[];
}

export interface CarsAspect {
    key: string;
    label: string;
}

export interface CarsResponse {
    passage: CarsPassage | null;
    rubric: string[];
    debate_aspects?: CarsAspect[];
}

export interface CarsDebateReply {
    reply: string;
    critique: string;
    skill: string;
    source: string;
}

export interface CarsDebateResponse {
    ai_enabled: boolean;
    reply: CarsDebateReply | null;
}

// Round-based debate (4 aspects, win 3/4).
export interface CarsRoundResult {
    won: boolean;
    reply: string;
    note: string;
    source: string;
}

export interface CarsReview {
    did_well: string[];
    work_on: string[];
    source: string;
}

export const SECTION_NAMES: Record<string, string> = {
    bb: "Bio/Biochem",
    cp: "Chem/Phys",
    ps: "Psych/Soc",
    cars: "CARS",
};

export const CONFIDENCE_LABELS: { key: string; label: string }[] = [
    { key: "guessing", label: "Guessing" },
    { key: "leaning", label: "Fairly Sure" },
    { key: "certain", label: "Certain" },
];
