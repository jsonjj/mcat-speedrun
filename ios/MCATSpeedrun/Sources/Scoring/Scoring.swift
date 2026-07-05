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

    // MARK: - Coach facts (compact scores summary for the AI coach)

    /// The compact JSON the AI coach is grounded in — overall and per-section
    /// memory/performance/readiness points + coverage — from the shared engine's
    /// scores. Matches the desktop coach's `facts`. Returns "{}" if unavailable.
    static func coachFactsJSON(app: AppState, progress: ProgressStore) -> String {
        guard let full = fullScores(app: app, progress: progress) else { return "{}" }

        func point(_ b: FullBlock) -> Any {
            b.abstained ? NSNull() : (b.point.map { $0 as Any } ?? NSNull())
        }

        var sectionFacts: [String: Any] = [:]
        for (code, s) in full.sections {
            sectionFacts[code] = [
                "coverage_pct": s.coveragePct,
                "memory": point(s.memory),
                "performance": point(s.performance),
                "readiness": point(s.readiness),
            ]
        }
        let facts: [String: Any] = [
            "memory": point(full.memory),
            "performance": point(full.performance),
            "readiness": point(full.readiness),
            "pacing_slow_pct": progress.pacingSlowPct,
            "sections": sectionFacts,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: facts),
            let str = String(data: data, encoding: .utf8)
        else { return "{}" }
        return str
    }

    /// True when there's at least some measured evidence to coach on (avoids a
    /// wasted API call + a generic tip on a brand-new account).
    static func hasEvidence(app: AppState, progress: ProgressStore) -> Bool {
        guard let full = fullScores(app: app, progress: progress) else { return false }
        return !(full.memory.abstained && full.performance.abstained && full.readiness.abstained)
    }

    // MARK: - Section ranking (for the dashboard weakest/strongest popups)

    enum Measure { case memory, performance }

    /// Sections (non-abstained) ranked ascending by the given measure's point.
    /// Used to name the subjects behind the strongest badge and to point the
    /// weakest badge at a specific practice. Mirrors the desktop dashboard.
    static func sectionsRanked(app: AppState, progress: ProgressStore, measure: Measure)
        -> [(code: SectionCode, point: Double)]
    {
        guard let full = fullScores(app: app, progress: progress) else { return [] }
        var out: [(SectionCode, Double)] = []
        for code in order {
            guard let s = full.sections[code.rawValue] else { continue }
            let block = measure == .memory ? s.memory : s.performance
            if !block.abstained, let point = block.point { out.append((code, point)) }
        }
        return out.sorted { $0.1 < $1.1 }.map { (code: $0.0, point: $0.1) }
    }

    // MARK: - Trend sparklines (rolling accuracy from the shared log)

    struct Trend {
        var recall: [Double] = []
        var applied: [Double] = []
        var recallDelta: Int = 0
        var appliedDelta: Int = 0
    }

    /// Real recall/applied trend series (rolling-window accuracy over the merged
    /// event log in time order) + net deltas — the SAME algorithm the desktop
    /// account endpoint uses, so the sparklines match across devices.
    static func trends(progress: ProgressStore) -> Trend {
        guard let data = progress.combinedLogJSON().data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return Trend() }
        let reviews = (obj["reviews"] as? [[String: Any]]) ?? []
        let attempts = (obj["attempts"] as? [[String: Any]]) ?? []
        func ts(_ d: [String: Any]) -> Int { (d["ts"] as? Int) ?? 0 }
        let recallFlags =
            reviews.sorted { ts($0) < ts($1) }.map { ($0["rating"] as? Int ?? 0) >= 3 }
        let appliedFlags =
            attempts.sorted { ts($0) < ts($1) }.map { ($0["first_correct"] as? Bool) ?? false }
        let (r, rd) = trendSeries(recallFlags)
        let (a, ad) = trendSeries(appliedFlags)
        return Trend(recall: r, applied: a, recallDelta: rd, appliedDelta: ad)
    }

    // MARK: - Activity counts (reps / sets, total + this week)

    struct Activity {
        var reps = 0
        var sets = 0
        var repsWeek = 0
        var attemptsWeek = 0
    }

    /// Unix-seconds timestamp of the earliest study event (review/attempt), or
    /// nil if there's no activity yet — the student's real prep start date.
    /// Cross-device consistent (same merged log as the desktop).
    static func startTimestamp(progress: ProgressStore) -> Int? {
        guard let data = progress.combinedLogJSON().data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let reviews = (obj["reviews"] as? [[String: Any]]) ?? []
        let attempts = (obj["attempts"] as? [[String: Any]]) ?? []
        let tss =
            (reviews + attempts)
            .compactMap { $0["ts"] as? Int }
            .filter { $0 > 0 }
        return tss.min()
    }

    /// Log counts for the score detail pages: total reviews (reps) and attempts
    /// (sets), plus the last-7-days counts. ts is Unix seconds (see ProgressStore).
    static func activity(progress: ProgressStore) -> Activity {
        guard let data = progress.combinedLogJSON().data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return Activity() }
        let reviews = (obj["reviews"] as? [[String: Any]]) ?? []
        let attempts = (obj["attempts"] as? [[String: Any]]) ?? []
        let cutoff = Int(Date().timeIntervalSince1970) - 7 * 86_400
        func ts(_ d: [String: Any]) -> Int { (d["ts"] as? Int) ?? 0 }
        return Activity(
            reps: reviews.count, sets: attempts.count,
            repsWeek: reviews.filter { ts($0) >= cutoff }.count,
            attemptsWeek: attempts.filter { ts($0) >= cutoff }.count)
    }

    private static func trendSeries(_ flags: [Bool]) -> ([Double], Int) {
        let n = flags.count
        guard n >= 4 else { return ([], 0) }
        let window = max(3, n / 3)
        var roll: [Double] = []
        for i in 0..<n {
            let seg = flags[max(0, i - window + 1)...i]
            roll.append((Double(seg.filter { $0 }.count) / Double(seg.count) * 100).rounded())
        }
        let k = 16
        let points: [Double] =
            roll.count <= k
            ? roll
            : (0..<k).map { j in
                roll[Int((Double(j) * Double(roll.count - 1) / Double(k - 1)).rounded())]
            }
        return (points, Int((points.last ?? 0) - (points.first ?? 0)))
    }

    // MARK: - Practice recommendation (weakest section + flashcards vs problems)

    /// The single "study this next" recommendation from the scores: the weakest
    /// section and whether flashcards or problems are more needed. Returns nil
    /// when there's no measured evidence yet (nothing to highlight).
    static func recommendedAction(app: AppState, progress: ProgressStore)
        -> (section: SectionCode, action: String)?
    {
        guard let full = fullScores(app: app, progress: progress) else { return nil }
        func pt(_ code: SectionCode, _ measure: String) -> Double? {
            guard let s = full.sections[code.rawValue] else { return nil }
            let b = measure == "memory" ? s.memory : s.performance
            return b.abstained ? nil : b.point
        }
        func weakness(_ code: SectionCode) -> Double {
            let p = pt(code, "performance")
            return p == nil ? 0.6 : 1 - p! / 100
        }
        func action(_ code: SectionCode) -> String {
            if code == .cars { return "problems" }
            let m = pt(code, "memory")
            let p = pt(code, "performance")
            if let m, let p, m < p - 8 { return "flashcards" }
            if m != nil, p == nil { return "flashcards" }
            return "problems"
        }
        let weakest = order.max(by: { weakness($0) < weakness($1) }) ?? .bb
        return (weakest, action(weakest))
    }

    private static func fullScores(app: AppState, progress: ProgressStore) -> FullScores? {
        let json = Engine.scores(
            state: progress.combinedLogJSON(),
            coverage: ContentStore.shared.coverageJSON(),
            external: "{}",
            diag: app.diagnosticKind ?? "")
        return decodeFull(json)
    }

    private struct FullBlock: Decodable {
        var abstained: Bool
        var point: Double?
    }
    private struct FullSection: Decodable {
        var coveragePct: Double
        var memory: FullBlock
        var performance: FullBlock
        var readiness: FullBlock
    }
    private struct FullScores: Decodable {
        var memory: FullBlock
        var performance: FullBlock
        var readiness: FullBlock
        var sections: [String: FullSection]
    }
    private static func decodeFull(_ json: String) -> FullScores? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(FullScores.self, from: data)
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
