// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Dashboard scores come from the SHARED Rust engine (Engine.scores over FFI),
// so iOS and desktop compute identical numbers from the same logic. This file
// just calls the engine, maps the result into the view models, and keeps the
// dev "Set mastery" override (a local display-only tool) in Swift.

import Foundation

enum Scoring {
    private static let order: [SectionCode] = [.bb, .cp, .ps, .cars]

    // MARK: - Entry point

    static func model(app: AppState, progress: ProgressStore) -> DashboardModel {
        let days = app.daysToGo ?? 0
        if let mastery = app.devMastery {
            return devModel(mastery: mastery, days: days, streak: app.streak)
        }
        let json = Engine.scores(
            state: progress.combinedLogJSON(),
            coverage: ContentStore.shared.coverageJSON(),
            external: "{}",
            diag: app.diagnosticKind ?? "")
        if let scores = decode(json) {
            return mapEngine(scores, days: days, streak: app.streak)
        }
        return emptyModel(days: days, streak: app.streak)
    }

    // MARK: - Engine result -> view model

    private static func mapEngine(_ s: EngineScores, days: Int, streak: Int)
        -> DashboardModel
    {
        var sections: [SectionReadiness] = []
        for code in order {
            guard let sec = s.sections[code.rawValue], !sec.readiness.abstained,
                let point = sec.readiness.point
            else {
                sections.append(
                    SectionReadiness(
                        code: code, low: 118, high: 118, point: 118, tone: .red,
                        abstained: true))
                continue
            }
            sections.append(
                SectionReadiness(
                    code: code, low: sec.readiness.low ?? 118,
                    high: sec.readiness.high ?? 118, point: point,
                    tone: toneForSection(point), abstained: false))
        }
        return DashboardModel(
            daysToGo: days, streak: streak,
            memory: block(s.memory, percent: true),
            performance: block(s.performance, percent: true),
            readiness: block(s.readiness, percent: false),
            sections: sections, estLow: s.estLow, estHigh: s.estHigh)
    }

    private static func block(_ b: EngineBlock, percent: Bool) -> ScoreBlock {
        guard !b.abstained, let point = b.point else {
            return ScoreBlock(
                low: nil, high: nil, point: nil, isPercent: percent, tone: .red,
                coveragePct: b.coveragePct, evidence: "Not enough evidence yet.",
                bestNext: "Keep practising to build evidence.", abstained: true)
        }
        let tone = percent ? toneForPct(point) : toneForTotal(point)
        return ScoreBlock(
            low: b.low, high: b.high, point: point, isPercent: percent, tone: tone,
            coveragePct: b.coveragePct, evidence: "Computed by the shared engine.",
            bestNext: "Keep practising across your weakest sections.",
            abstained: false)
    }

    private static func emptyModel(days: Int, streak: Int) -> DashboardModel {
        let abstainedPct = ScoreBlock(
            low: nil, high: nil, point: nil, isPercent: true, tone: .red,
            coveragePct: 0, evidence: "Not enough evidence yet.",
            bestNext: "Do some practice.", abstained: true)
        let abstainedTotal = ScoreBlock(
            low: nil, high: nil, point: nil, isPercent: false, tone: .red,
            coveragePct: 0, evidence: "Not enough evidence yet.",
            bestNext: "Do some practice.", abstained: true)
        let sections = order.map {
            SectionReadiness(
                code: $0, low: 118, high: 118, point: 118, tone: .red, abstained: true)
        }
        return DashboardModel(
            daysToGo: days, streak: streak, memory: abstainedPct,
            performance: abstainedPct, readiness: abstainedTotal, sections: sections,
            estLow: 0, estHigh: 0)
    }

    // MARK: - Dev override (mirrors the desktop dev "Set mastery")

    private static func devModel(mastery: Double, days: Int, streak: Int)
        -> DashboardModel
    {
        let secScore = sectionScoreInt(mastery / 100)
        let sections = order.map { code in
            SectionReadiness(
                code: code, low: Double(max(118, secScore - 1)),
                high: Double(min(132, secScore + 1)), point: Double(secScore),
                tone: toneForSection(Double(secScore)))
        }
        let total = secScore * 4
        let readiness = ScoreBlock(
            low: Double(total - 4), high: Double(total + 4), point: Double(total),
            isPercent: false, tone: toneForTotal(Double(total)), coveragePct: 1,
            evidence: "Dev override — readiness is the sum of section scores.",
            bestNext: "Dev override active.", abstained: false)
        let pct = ScoreBlock(
            low: max(0, mastery - 8), high: min(100, mastery + 8), point: mastery,
            isPercent: true, tone: toneForPct(mastery), coveragePct: 1,
            evidence: "Dev override.", bestNext: "Dev override active.",
            abstained: false)
        return DashboardModel(
            daysToGo: days, streak: streak, memory: pct, performance: pct,
            readiness: readiness, sections: sections, estLow: total - 4,
            estHigh: total + 4)
    }

    // MARK: - Decoding the engine's Scores JSON

    private struct EngineBlock: Decodable {
        var abstained: Bool
        var point: Double?
        var low: Double?
        var high: Double?
        var unit: String
        var coveragePct: Double
    }
    private struct EngineSection: Decodable {
        var readiness: EngineBlock
    }
    private struct EngineScores: Decodable {
        var memory: EngineBlock
        var performance: EngineBlock
        var readiness: EngineBlock
        var sections: [String: EngineSection]
        var estLow: Int
        var estHigh: Int
    }

    private static func decode(_ json: String) -> EngineScores? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(EngineScores.self, from: data)
    }

    // MARK: - Tone + section-score anchors (for display + dev override)

    private static func toneForPct(_ p: Double) -> EvidenceTone {
        p >= 85 ? .green : (p >= 60 ? .amber : .red)
    }
    private static func toneForSection(_ s: Double) -> EvidenceTone {
        s >= 128 ? .green : (s >= 125 ? .amber : .red)
    }
    private static func toneForTotal(_ t: Double) -> EvidenceTone {
        t >= 510 ? .green : (t >= 500 ? .amber : .red)
    }

    private static let anchors: [(Double, Double)] = [
        (0.00, 118), (0.25, 121), (0.40, 123), (0.50, 124), (0.55, 125),
        (0.65, 127), (0.75, 128), (0.85, 130), (0.92, 131), (1.00, 132),
    ]
    private static func toSectionScore(_ proportion: Double) -> Double {
        let p = max(0, min(1, proportion))
        for i in 1..<anchors.count {
            let (x0, y0) = anchors[i - 1]
            let (x1, y1) = anchors[i]
            if p <= x1 {
                if x1 == x0 { return y1 }
                let t = (p - x0) / (x1 - x0)
                return y0 + t * (y1 - y0)
            }
        }
        return anchors.last!.1
    }
    private static func sectionScoreInt(_ proportion: Double) -> Int {
        Int(toSectionScore(proportion).rounded())
    }
}
