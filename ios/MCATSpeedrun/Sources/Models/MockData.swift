// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Placeholder content so the SwiftUI screens render before the Rust engine's
// MCAT services are wired in over the FFI. Swap these for live engine calls
// later; the view code should not need to change.

import Foundation

enum MockData {
    static let dashboard = DashboardModel(
        daysToGo: 119,
        streak: 1,
        memory: ScoreBlock(
            low: 74, high: 86, point: 80, isPercent: true, tone: .amber,
            coveragePct: 1.0,
            evidence: "Graded recall on your memory cards (FSRS).",
            bestNext: "Keep daily reviews to lift recall above 85%."
        ),
        performance: ScoreBlock(
            low: 62, high: 78, point: 70, isPercent: true, tone: .amber,
            coveragePct: 0.8,
            evidence: "First-answer accuracy on fresh questions.",
            bestNext: "Do a Performance Set in your weakest section."
        ),
        readiness: ScoreBlock(
            low: 512, high: 520, point: 516, isPercent: false, tone: .amber,
            coveragePct: 0.75,
            evidence: "Blends coverage, performance and calibration.",
            bestNext: "Broaden coverage in Psychology to tighten the range."
        ),
        sections: [
            SectionReadiness(code: .bb, low: 129, high: 131, point: 130, tone: .green),
            SectionReadiness(code: .cp, low: 129, high: 131, point: 130, tone: .green),
            SectionReadiness(code: .ps, low: 126, high: 128, point: 127, tone: .amber),
            SectionReadiness(code: .cars, low: 128, high: 130, point: 129, tone: .amber),
        ],
        estLow: 512,
        estHigh: 520
    )

    /// Today's roadmap. This is a DETERMINISTIC mirror of the desktop planner:
    /// same fixed section order, same phase mix, same minutes scaling, and the
    /// same stable block keys (slugs) — so roadmap progress syncs by key across
    /// desktop and iOS. foundation = per-section lessons; sharpen = fewer lessons
    /// + full-lengths; final = only Mini-MCATs + full run-throughs (flashcards
    /// disabled). CARS is MCQ practice (no debate).
    private struct Template {
        var keyBase: String
        var label: String
        var minutes: Int
        var activity: Activity
        var sub: String
        var destination: StudyDestination
    }

    private static func short(_ s: SectionCode) -> String {
        switch s {
        case .bb: return "Bio/Biochem"
        case .cp: return "Chem/Phys"
        case .ps: return "Psych/Soc"
        case .cars: return "CARS"
        }
    }

    static func roadmap(phase: String, dailyMinutes: Int) -> [RoadmapItem] {
        let target = max(15, dailyMinutes)
        let miniCount = target >= 60 ? 20 : (target >= 40 ? 16 : 12)
        let order: [SectionCode] = [.bb, .cp, .ps, .cars]

        func mini() -> Template {
            Template(
                keyBase: "mini-mcat", label: "Mini-MCAT", minutes: 15,
                activity: .sectionPractice, sub: "Section Practice",
                destination: .questions(
                    QuizConfig(title: "Mini-MCAT", sections: SectionCode.allCases,
                               count: miniCount, seconds: 90)))
        }
        func full() -> Template {
            Template(
                keyBase: "full-length", label: "Full-Length Run-Through", minutes: 20,
                activity: .sectionPractice, sub: "All sections",
                destination: .questions(
                    QuizConfig(title: "Full-Length", sections: SectionCode.allCases,
                               count: 16, seconds: 90)))
        }
        func maintenance() -> Template {
            Template(
                keyBase: "maintenance", label: "Memory Maintenance", minutes: 10,
                activity: .spacedReview, sub: "Spaced Review",
                destination: .flashcards(sections: SectionCode.allCases))
        }
        func application(_ s: SectionCode) -> Template {
            let label = s == .cars ? "CARS Practice" : "\(short(s)) Application"
            return Template(
                keyBase: "\(s.rawValue)-application", label: label, minutes: 15,
                activity: .performanceSet, sub: short(s),
                destination: .questions(
                    QuizConfig(title: label, sections: [s], count: 10, seconds: 90)))
        }
        func recall(_ s: SectionCode) -> Template {
            Template(
                keyBase: "\(s.rawValue)-recall", label: "\(short(s)) Recall", minutes: 10,
                activity: .spacedReview, sub: short(s),
                destination: .flashcards(sections: [s]))
        }

        var items: [RoadmapItem] = []
        var used = 0
        var occ: [String: Int] = [:]

        func add(_ t: Template) {
            occ[t.keyBase, default: 0] += 1
            let n = occ[t.keyBase]!
            let minutes = min(20, t.minutes)
            items.append(
                RoadmapItem(
                    key: "\(t.keyBase)-\(n)",
                    label: t.label + (n > 1 ? " #\(n)" : ""),
                    sub: t.sub, minutes: minutes, activity: t.activity,
                    status: .locked, destination: t.destination))
            used += minutes
        }

        // Always open the day with a Mini-MCAT.
        add(mini())

        var menu: [Template] = []
        switch phase {
        case "final":
            menu = [mini(), full(), mini(), full()]
        case "sharpen":
            menu = [
                mini(), application(.bb), application(.cp), full(), recall(.bb),
                maintenance(),
            ]
        default:
            for s in order {
                menu.append(application(s))
                if s != .cars { menu.append(recall(s)) }
            }
            menu.append(maintenance())
        }

        var idx = 0
        while used < target - 4 && items.count < 16 {
            let item = menu[idx % menu.count]
            if used + min(20, item.minutes) > target + 6 { break }
            add(item)
            idx += 1
        }
        return items
    }

    static let flashcards: [Flashcard] = [
        Flashcard(front: "What is the isoelectric point (pI)?",
                  back: "The pH at which a molecule carries no net electrical charge.", section: .bb),
        Flashcard(front: "Neurotransmitter released at the neuromuscular junction?",
                  back: "Acetylcholine.", section: .bb),
        Flashcard(front: "Define the Doppler effect.",
                  back: "The change in observed frequency due to relative motion between source and observer.", section: .cp),
    ]

    static let questions: [Question] = [
        Question(section: .bb,
                 stem: "Which amino acid is most likely to be found in the interior of a globular protein in aqueous solution?",
                 choices: [
                    Choice(letter: "A", text: "Lysine"),
                    Choice(letter: "B", text: "Valine"),
                    Choice(letter: "C", text: "Glutamate"),
                    Choice(letter: "D", text: "Serine"),
                 ], correct: 1,
                 explanation: "Valine is nonpolar/hydrophobic, so it sequesters away from water in the protein core."),
        Question(section: .cp,
                 stem: "A wave doubles in frequency while speed is held constant. Its wavelength:",
                 choices: [
                    Choice(letter: "A", text: "Doubles"),
                    Choice(letter: "B", text: "Is halved"),
                    Choice(letter: "C", text: "Is unchanged"),
                    Choice(letter: "D", text: "Quadruples"),
                 ], correct: 1,
                 explanation: "v = fλ. With v constant, doubling f halves λ."),
        Question(section: .bb,
                 stem: "During intense exercise, muscle cells regenerate NAD⁺ anaerobically primarily through:",
                 choices: [
                    Choice(letter: "A", text: "The citric acid cycle"),
                    Choice(letter: "B", text: "Oxidative phosphorylation"),
                    Choice(letter: "C", text: "Lactic acid fermentation"),
                    Choice(letter: "D", text: "Beta-oxidation"),
                 ], correct: 2,
                 explanation: "Fermentation reduces pyruvate to lactate, oxidizing NADH back to NAD⁺ so glycolysis can continue without oxygen."),
        Question(section: .cp,
                 stem: "A 2 kg cart accelerates at 3 m/s². What is the net force acting on it?",
                 choices: [
                    Choice(letter: "A", text: "1.5 N"),
                    Choice(letter: "B", text: "5 N"),
                    Choice(letter: "C", text: "6 N"),
                    Choice(letter: "D", text: "9 N"),
                 ], correct: 2,
                 explanation: "F = ma = (2 kg)(3 m/s²) = 6 N."),
        Question(section: .ps,
                 stem: "Which memory store has essentially unlimited capacity and the longest duration?",
                 choices: [
                    Choice(letter: "A", text: "Sensory memory"),
                    Choice(letter: "B", text: "Short-term memory"),
                    Choice(letter: "C", text: "Working memory"),
                    Choice(letter: "D", text: "Long-term memory"),
                 ], correct: 3,
                 explanation: "Long-term memory has no known capacity limit and can persist for years; the others are brief and limited."),
        Question(section: .ps,
                 stem: "The resting membrane potential of a neuron is maintained primarily by:",
                 choices: [
                    Choice(letter: "A", text: "The Na⁺/K⁺ ATPase"),
                    Choice(letter: "B", text: "Voltage-gated Ca²⁺ channels"),
                    Choice(letter: "C", text: "Ligand-gated Cl⁻ channels"),
                    Choice(letter: "D", text: "Gap junctions"),
                 ], correct: 0,
                 explanation: "The Na⁺/K⁺ ATPase pumps 3 Na⁺ out and 2 K⁺ in, sustaining the gradients behind the ~ –70 mV resting potential."),
        Question(section: .cars,
                 stem: "A critic argues that standardized tests measure test-taking skill more than real knowledge. This argument depends on assuming that:",
                 choices: [
                    Choice(letter: "A", text: "Standardized tests are too long"),
                    Choice(letter: "B", text: "Test-taking skill and knowledge can be meaningfully separated"),
                    Choice(letter: "C", text: "All students prepare for tests equally"),
                    Choice(letter: "D", text: "Knowledge cannot be measured at all"),
                 ], correct: 1,
                 explanation: "The claim only works if the two things can be distinguished; if skill and knowledge were inseparable, the contrast would collapse."),
        Question(section: .cars,
                 stem: "An author writes: 'Once a number is attached to work, students optimize for the number, not understanding.' The author's main point is that grades:",
                 choices: [
                    Choice(letter: "A", text: "Should be replaced with written feedback"),
                    Choice(letter: "B", text: "Are impossible to calculate fairly"),
                    Choice(letter: "C", text: "Can redirect motivation away from genuine learning"),
                    Choice(letter: "D", text: "Are useful only in advanced courses"),
                 ], correct: 2,
                 explanation: "The passage centers on how grading shifts what students optimize for; it never argues the other, more specific claims."),
    ]

    static let cars = CarsPassage(
        passage: "The author argues that grading distorts learning. Once a number is attached to a piece of work, students optimize for the number rather than for understanding, and curiosity quietly dies. Teachers, too, begin to teach what is easy to measure. The author concedes that some evaluation is unavoidable, but insists the dominance of the grade has hollowed out the very thing school exists to cultivate.",
        authorClaim: "The dominance of grades undermines genuine learning.",
        prompts: [
            CarsPrompt(prompt: "What is the author trying to make you accept?", skill: "Foundations of Comprehension"),
            CarsPrompt(prompt: "Argue against the author: what does a defender of grades say?", skill: "Reasoning Within the Text"),
            CarsPrompt(prompt: "Now defend the author: state the strongest version of the claim.", skill: "Reasoning Within the Text"),
            CarsPrompt(prompt: "New condition: grades are pass/fail only. Stronger, weaker, or unchanged?", skill: "Reasoning Beyond the Text"),
        ],
        strongRebuttal: "The strongest challenge targets the hidden assumption that measurement and motivation are opposed; well-designed grades can signal mastery and guide effort rather than replace curiosity.",
        strongDefense: "The strongest defense reframes the claim as being about dominance, not existence: when the grade becomes the goal, intrinsic motivation is crowded out even if some evaluation remains useful.",
        rubric: [
            "I restated the author's main claim in my own words",
            "I stayed inside the passage's evidence (no outside facts)",
            "I argued both sides, not just my own opinion",
            "I judged the new condition by the argument's logic",
        ]
    )
}
