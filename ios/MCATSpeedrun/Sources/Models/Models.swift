// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Shared data models for the MCAT Speedrun iOS UI. These mirror the desktop web
// types. For now screens render from MockData; later these are populated from
// the Rust engine over the FFI.

import SwiftUI

enum ScoreKind: String, CaseIterable, Identifiable {
    case memory, performance, readiness
    var id: String { rawValue }
    var title: String {
        switch self {
        case .memory: return "Memory Recall"
        case .performance: return "Applied Under Exam Conditions"
        case .readiness: return "Overall Readiness"
        }
    }
    var icon: String {
        switch self {
        case .memory: return "brain.head.profile"
        case .performance: return "scope"
        case .readiness: return "gauge.medium"
        }
    }
    var means: String {
        switch self {
        case .memory: return "Can you recall prerequisites right now?"
        case .performance: return "Can you apply it to new questions?"
        case .readiness: return "Your likely MCAT range today."
        }
    }
}

enum SectionCode: String, CaseIterable, Identifiable {
    case bb, cp, ps, cars
    var id: String { rawValue }
    var word: String {
        switch self {
        case .bb: return "Biology"
        case .cp: return "Chemistry"
        case .ps: return "Psychology"
        case .cars: return "CARS"
        }
    }
    var abbr: String {
        switch self {
        case .bb: return "B/B"
        case .cp: return "C/P"
        case .ps: return "P/S"
        case .cars: return "CARS"
        }
    }
    var icon: String {
        switch self {
        case .bb: return "leaf.fill"
        case .cp: return "atom"
        case .ps: return "person.2.fill"
        case .cars: return "book.fill"
        }
    }
}

enum EvidenceTone {
    case green, amber, red
    var color: Color {
        switch self {
        case .green: return Theme.green
        case .amber: return Theme.amber
        case .red: return Theme.red
        }
    }
    var label: String {
        switch self {
        case .green: return "Strong Evidence"
        case .amber: return "Moderate Evidence"
        case .red: return "Thin Evidence"
        }
    }
}

struct ScoreBlock: Identifiable {
    let id = UUID()
    var low: Double?
    var high: Double?
    var point: Double?
    var isPercent: Bool
    var tone: EvidenceTone
    var coveragePct: Double
    var evidence: String
    var bestNext: String
    var abstained: Bool = false

    /// Big headline value, e.g. "80%" or "512 – 520".
    var display: String {
        if abstained { return "—" }
        if isPercent, let p = point { return "\(Int(p.rounded()))%" }
        if let l = low, let h = high {
            return "\(Int(l.rounded())) – \(Int(h.rounded()))"
        }
        if let p = point { return "\(Int(p.rounded()))" }
        return "—"
    }
}

struct SectionReadiness: Identifiable {
    let id = UUID()
    var code: SectionCode
    var low: Double
    var high: Double
    var point: Double
    var tone: EvidenceTone
    var abstained: Bool = false
}

struct DashboardModel {
    var daysToGo: Int
    var streak: Int
    var memory: ScoreBlock
    var performance: ScoreBlock
    var readiness: ScoreBlock
    var sections: [SectionReadiness]
    var estLow: Int
    var estHigh: Int
}

enum Activity {
    case spacedReview, performanceSet, sectionPractice
    var color: Color {
        switch self {
        case .spacedReview: return Theme.cyan
        case .performanceSet: return Theme.amber
        case .sectionPractice: return Theme.accent
        }
    }
    var label: String {
        switch self {
        case .spacedReview: return "Spaced Review"
        case .performanceSet: return "Performance Set"
        case .sectionPractice: return "Section Practice"
        }
    }
    var icon: String {
        switch self {
        case .spacedReview: return "sparkles"
        case .performanceSet: return "target"
        case .sectionPractice: return "book.fill"
        }
    }
}

enum BlockStatus { case done, active, locked }

/// A study task. `destination` tells screens which study view to open.
enum StudyDestination { case flashcards(sections: [SectionCode]), questions(QuizConfig), cars }

struct RoadmapItem: Identifiable {
    let id = UUID()
    /// Stable slug shared with the desktop planner (e.g. "bb-application-1"), so
    /// completion syncs by key across devices.
    var key: String
    var label: String
    var sub: String
    var minutes: Int
    var activity: Activity
    var status: BlockStatus
    var destination: StudyDestination
}

struct QuizConfig: Hashable {
    var title: String
    var sections: [SectionCode]
    var count: Int
    var seconds: Int?
}

struct Flashcard: Identifiable {
    let id = UUID()
    var front: String
    var back: String
    var section: SectionCode
    var topicIds: [String] = []
    /// Stable content key shared with the engine (for FSRS per-card state).
    var key: String = ""
}

struct Choice: Identifiable {
    let id = UUID()
    var letter: String
    var text: String
}

struct Question: Identifiable {
    let id = UUID()
    var section: SectionCode
    var stem: String
    var choices: [Choice]
    var correct: Int
    var explanation: String
    var topicIds: [String] = []
    /// Stable content key shared with the engine (for attempt de-duplication).
    var key: String = ""
}

struct CarsPrompt: Identifiable {
    let id = UUID()
    var prompt: String
    var skill: String
}

struct CarsPassage {
    var passage: String
    var authorClaim: String
    var prompts: [CarsPrompt]
    var strongRebuttal: String
    var strongDefense: String
    var rubric: [String]
}

// Order + wording match the desktop app exactly (low -> high confidence). The
// raw value is the stable key ("guessing"/"leaning"/"certain") shared with the
// backend; `label` is what the user sees.
enum ConfidenceLevel: String, CaseIterable, Identifiable {
    case guessing
    case leaning
    case certain
    var id: String { rawValue }
    var label: String {
        switch self {
        case .guessing: return "Guessing"
        case .leaning: return "Fairly Sure"
        case .certain: return "Certain"
        }
    }
}
