// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import type { RoadmapBlock, ScoreBlock } from "./types";

// A color per block, based on what you're doing. Section drives the hue for
// study blocks; special kinds (Mini-MCAT, memory maintenance, full-length) get
// their own colors.
const SECTION_COLORS: Record<string, string> = {
    bb: "#15a06e", // Bio/Biochem - green
    cp: "#2f6df0", // Chem/Phys - blue
    ps: "#7c3aed", // Psych/Soc - purple
    cars: "#d97706", // CARS - amber
};

export function blockColor(block: RoadmapBlock): string {
    if (block.kind === "mini_mcat") {
        return "#4f46e5"; // indigo - the daily exam-form block
    }
    if (block.kind === "full_length_review") {
        return "#e11d48"; // rose - heavier review
    }
    if (block.kind === "memory" && !block.section) {
        return "#0d9488"; // teal - general maintenance
    }
    if (block.section && SECTION_COLORS[block.section]) {
        return SECTION_COLORS[block.section];
    }
    return "#4f46e5";
}

// Pick black or white text for legibility on a given solid background color.
export function textColor(hex: string): string {
    const h = hex.replace("#", "");
    const r = parseInt(h.slice(0, 2), 16);
    const g = parseInt(h.slice(2, 4), 16);
    const b = parseInt(h.slice(4, 6), 16);
    // Relative luminance (sRGB approximation).
    const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return luminance > 0.62 ? "#1a2332" : "#ffffff";
}

export const SECTION_COLOR: Record<string, string> = {
    bb: "#15a06e",
    cp: "#2f6df0",
    ps: "#7c3aed",
    cars: "#d97706",
};

// The three headline scores each get a distinct, consistent color so they read
// the same way on the dashboard, the account page and their detail pages.
export const SCORE_COLOR: Record<string, string> = {
    memory: "#0d9488", // teal
    performance: "#2563eb", // blue
    readiness: "#7c3aed", // violet
};

// Section labels for the score report / breakdown.
export const SECTION_ABBR: Record<string, string> = {
    bb: "B/B",
    cp: "C/P",
    ps: "P/S",
    cars: "CARS",
};

// Single-word section names (used on score displays instead of abbreviations).
export const SECTION_WORD: Record<string, string> = {
    bb: "Biology",
    cp: "Chemistry",
    ps: "Psychology",
    cars: "CARS",
};

export const SECTION_FULL: Record<string, string> = {
    bb: "Biological and Biochemical Foundations",
    cp: "Chemical and Physical Foundations",
    ps: "Psychological, Social, and Biological Foundations",
    cars: "Critical Analysis and Reasoning Skills",
};

// Evidence strength shown on score cards: maps the score's confidence (or
// abstention) onto the green / amber / red language used in the mockups.
export type Tone = "green" | "amber" | "red";

const TONE_VARS: Record<Tone, string> = {
    green: "var(--mcat-green)",
    amber: "var(--mcat-amber)",
    red: "var(--mcat-red)",
};

export function toneVar(tone: Tone): string {
    return TONE_VARS[tone];
}

export function evidence(b: ScoreBlock): { tone: Tone; label: string } {
    if (b.abstained) {
        return { tone: "red", label: "Abstaining" };
    }
    if (b.confidence === "high") {
        return { tone: "green", label: "Strong Evidence" };
    }
    if (b.confidence === "medium" || b.confidence === "low-medium") {
        return { tone: "amber", label: "Moderate Evidence" };
    }
    return { tone: "red", label: "Thin Evidence" };
}

// Activity type (color + icon + label) for a roadmap node, matching the legend:
// Spaced Review (cyan) · Performance Set (amber) · Section Practice (blue).
// Green is reserved for completed nodes so it can't be confused with recall.
export function activityMeta(block: RoadmapBlock): {
    label: string;
    color: string;
    icon: string;
} {
    if (block.kind === "memory") {
        return { label: "Spaced Review", color: "var(--mcat-cyan)", icon: "spark" };
    }
    if (block.kind === "performance") {
        return { label: "Performance Set", color: "var(--mcat-amber)", icon: "target" };
    }
    if (block.kind === "full_length_review") {
        return { label: "Full Length", color: "var(--mcat-blue)", icon: "clock" };
    }
    // mini_mcat, cars and anything else are exam-style section practice.
    return { label: "Section Practice", color: "var(--mcat-blue)", icon: "book" };
}

// How many items a roadmap block should serve, derived from its time budget.
function roadmapCount(block: RoadmapBlock): number {
    if (block.kind === "memory") {
        // Flashcards are quick (~45s each).
        return Math.min(30, Math.max(6, Math.round(block.minutes / 0.8)));
    }
    // Question-based tasks (~1.5 min/question).
    let n = Math.min(40, Math.max(5, Math.round(block.minutes / 1.5)));
    if (block.kind === "mini_mcat" || block.kind === "full_length_review") {
        n = Math.max(4, Math.round(n / 4) * 4); // even across the four sections
    }
    return n;
}

// Map a roadmap block to the page that actually does that task. We tag the URL
// with from=roadmap (so the nav stays on "Roadmap", not "Extra Practice") and
// the block id (so finishing the task marks that block done).
export function blockRoute(block: RoadmapBlock): string {
    const q = new URLSearchParams({
        from: "roadmap",
        block: block.id,
        count: String(roadmapCount(block)),
    });
    let base: string;
    if (block.kind === "cars") {
        base = "/mcat/cars";
    } else if (block.kind === "memory") {
        base = "/mcat/flashcards";
        if (block.section) {
            q.set("section", block.section);
        }
    } else if (block.kind === "performance") {
        base = "/mcat/mini";
        if (block.section) {
            q.set("section", block.section);
        }
    } else {
        // mini_mcat and full_length_review are all-sections question sets.
        base = "/mcat/mini";
    }
    return `${base}?${q.toString()}`;
}
