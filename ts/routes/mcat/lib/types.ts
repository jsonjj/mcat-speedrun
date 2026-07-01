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
    daily_minutes: number;
    onboarding_done: boolean;
    diagnostic_done: boolean;
    diagnostic_kind: string | null;
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

export interface RoadmapBlock {
    id: string;
    kind: string;
    section: string | null;
    mode: string;
    label: string;
    minutes: number;
    required: boolean;
    completed: boolean;
    meta: Record<string, unknown>;
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
}

export interface AccountData {
    profile: Profile;
    streak: Streak;
    scores: Scores | null;
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

export interface CarsResponse {
    passage: CarsPassage | null;
    rubric: string[];
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
