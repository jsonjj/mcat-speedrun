// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Detail for a single score (Memory / Applied / Readiness). Mirrors the desktop
// score page: a tinted hero (value + trend), quick stats, a by-section
// breakdown, and ONE contextual "do this next" action that launches the exact
// targeted practice — so every screen ladders up to a score.

import SwiftUI

struct ScoreDetailView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var progress: ProgressStore
    var kind: ScoreKind

    private static let reviewsGate = 100

    private var model: DashboardModel { Scoring.model(app: app, progress: progress) }
    private var block: ScoreBlock {
        switch kind {
        case .memory: return model.memory
        case .performance: return model.performance
        case .readiness: return model.readiness
        }
    }

    private var trend: Scoring.Trend { Scoring.trends(progress: progress) }
    private var activity: Scoring.Activity { Scoring.activity(progress: progress) }
    private var series: [Double] { kind == .memory ? trend.recall : trend.applied }

    // Sections ranked (ascending) by the relevant measure. Readiness sharpens the
    // weakest performance section, matching the desktop page.
    private var ranked: [(code: SectionCode, point: Double)] {
        Scoring.sectionsRanked(
            app: app, progress: progress,
            measure: kind == .memory ? .memory : .performance)
    }
    private var weakest: (code: SectionCode, point: Double)? { ranked.first }
    private var best: (code: SectionCode, point: Double)? { ranked.last }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if kind == .readiness {
                    readinessContent
                } else {
                    measureContent
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Memory / Applied

    @ViewBuilder private var measureContent: some View {
        let c = block.tone.color
        let week = kind == .memory ? activity.repsWeek : activity.attemptsWeek

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(kind.title).font(Theme.font(18, .heavy)).foregroundStyle(Theme.text)
                Spacer()
                chip(block.tone.label, color: c)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(block.display).font(Theme.font(50, .heavy)).foregroundStyle(c)
                if week > 0 { chip("\(week) this week", color: c) }
            }
            if series.count > 1 {
                Sparkline(points: series, color: c)
                    .frame(height: 44).padding(.top, 4)
                HStack {
                    Text("4 wks ago")
                    Spacer()
                    Text("now")
                }
                .font(Theme.font(11, .heavy)).foregroundStyle(c.opacity(0.8))
            }
        }
        .heroBox(c)

        HStack(spacing: 12) {
            tile(
                label: kind == .memory ? "Reps logged" : "Sets logged",
                value: "\(kind == .memory ? activity.reps : activity.sets)")
            if kind == .memory {
                tile(label: "Best section", value: best?.code.word ?? "—", small: true)
            } else {
                tile(
                    label: "First-try accuracy",
                    value: block.abstained ? "—" : "\(Int((block.point ?? 0).rounded()))%",
                    small: true, color: Theme.green)
            }
        }

        bySection

        doNextCTA
    }

    // MARK: - Readiness

    @ViewBuilder private var readinessContent: some View {
        let c = block.tone.color
        if block.abstained {
            let reviews = activity.reps
            let gate = Self.reviewsGate
            let pct = min(1, Double(reviews) / Double(gate))
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(kind.title).font(Theme.font(18, .heavy))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    chip("Abstaining", color: c)
                }
                Text("Not enough evidence yet to give you an honest number.")
                    .font(Theme.font(16, .bold)).foregroundStyle(c)
                HStack {
                    Text("\(reviews) of \(gate) reviews")
                    Spacer()
                    Text("\(max(0, gate - reviews)) to unlock")
                }
                .font(Theme.font(13, .heavy)).foregroundStyle(c)
                progressTrack(pct, color: c)
            }
            .heroBox(c)

            infoCard(
                eyebrow: "Why it's blank",
                bullets: [
                    "Readiness combines recall and applied — it needs enough of both to be trustworthy.",
                    "We'd rather show nothing than a number you can't rely on.",
                ])
            infoCard(
                eyebrow: "Unlocks at \(Self.reviewsGate)",
                bullets: ["A calibrated 472–528 estimate", "Per-section score ranges"],
                check: true)

            ctaCard(
                eyebrow: "Closest to unlocking", title: "Do a review set",
                sub: "Each set ≈ 8 reviews · 15 min"
            ) { FlashcardsView() }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(kind.title).font(Theme.font(18, .heavy))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    chip(block.tone.label, color: c)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(block.display).font(Theme.font(46, .heavy)).foregroundStyle(c)
                    Text("/ 528").font(Theme.font(20, .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .heroBox(c)

            NavigationLink { BreakdownView() } label: {
                HStack {
                    Spacer()
                    Text("See full breakdown").font(Theme.font(15, .bold))
                    Image(systemName: "arrow.right").font(Theme.font(13, .bold))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 18).padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain).tapSound()

            if let w = weakest {
                ctaCard(
                    eyebrow: "Sharpen the weakest area",
                    title: "Timed set — \(w.code.word)", sub: "Most to gain · 15 min"
                ) { QuestionRunnerView(config: set(w.code)) }
            }
        }
    }

    // MARK: - By-section breakdown

    @ViewBuilder private var bySection: some View {
        let order: [SectionCode] = [.bb, .cp, .ps, .cars]
        let points = Dictionary(uniqueKeysWithValues: ranked.map { ($0.code, $0.point) })
        VStack(alignment: .leading, spacing: 12) {
            Text("By section").font(Theme.font(11.5, .heavy)).tracking(0.6)
                .textCase(.uppercase).foregroundStyle(Theme.muted)
            if points.isEmpty {
                Text("No section data yet — do a set to fill this in.")
                    .font(Theme.font(14, .semibold)).foregroundStyle(Theme.muted)
            } else {
                ForEach(order.filter { points[$0] != nil }, id: \.self) { code in
                    let p = points[code] ?? 0
                    HStack(spacing: 12) {
                        Text(code.word).font(Theme.font(15, .bold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 104, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.track)
                                Capsule().fill(barColor(p))
                                    .frame(width: max(6, geo.size.width * (p / 100)))
                            }
                        }
                        .frame(height: 10)
                        Text("\(Int(p.rounded()))%").font(Theme.font(14, .heavy))
                            .foregroundStyle(Theme.text)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Do-this-next CTA (memory / applied)

    @ViewBuilder private var doNextCTA: some View {
        if let w = weakest {
            if kind == .memory {
                ctaCard(
                    eyebrow: "Do this next", title: "\(w.code.word) flashcards",
                    sub: "Your weakest section · 10 min"
                ) { FlashcardsView(sections: [w.code]) }
            } else {
                ctaCard(
                    eyebrow: "Keep the momentum",
                    title: "Timed set — \(w.code.word)", sub: "Most to gain · 15 min"
                ) { QuestionRunnerView(config: set(w.code)) }
            }
        } else {
            ctaCard(
                eyebrow: "Do this next",
                title: kind == .memory ? "A memory block" : "A question set",
                sub: kind == .memory ? "10 min" : "15 min"
            ) {
                if kind == .memory { FlashcardsView() } else {
                    QuestionRunnerView(
                        config: QuizConfig(
                            title: "Mini-MCAT", sections: [.bb, .cp, .ps, .cars],
                            count: 12, seconds: 120))
                }
            }
        }
    }

    // MARK: - Reusable pieces

    private func chip(_ text: String, color: Color) -> some View {
        Text(text).font(Theme.font(12.5, .heavy)).foregroundStyle(color)
            .padding(.horizontal, 11).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    private func tile(label: String, value: String, small: Bool = false, color: Color? = nil)
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.font(13, .semibold)).foregroundStyle(Theme.muted)
            Text(value).font(Theme.font(small ? 22 : 30, .heavy))
                .foregroundStyle(color ?? Theme.text).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
    }

    private func progressTrack(_ pct: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.14))
                Capsule().fill(color).frame(width: max(8, geo.size.width * pct))
            }
        }
        .frame(height: 12)
    }

    private func infoCard(eyebrow: String, bullets: [String], check: Bool = false)
        -> some View
    {
        VStack(alignment: .leading, spacing: 12) {
            Text(eyebrow).font(Theme.font(11.5, .heavy)).tracking(0.6)
                .textCase(.uppercase).foregroundStyle(Theme.muted)
            ForEach(bullets, id: \.self) { b in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: check ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15))
                        .foregroundStyle(check ? Theme.green : Theme.accent)
                    Text(b).font(Theme.font(15, .medium)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .cardStyle()
    }

    private func ctaCard<Dest: View>(
        eyebrow: String, title: String, sub: String, @ViewBuilder dest: () -> Dest
    ) -> some View {
        NavigationLink { dest() } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased()).font(Theme.font(11.5, .heavy)).tracking(0.6)
                    .foregroundStyle(Theme.accent)
                Text(title).font(Theme.font(18, .heavy)).foregroundStyle(Theme.text)
                Text(sub).font(Theme.font(13.5, .semibold)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.accent.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.accent.opacity(0.4), lineWidth: 1.5))
        }
        .buttonStyle(.plain).tapSound()
    }

    private func barColor(_ p: Double) -> Color {
        p >= 70 ? Theme.green : (p >= 45 ? Theme.amber : Theme.red)
    }

    private func set(_ code: SectionCode) -> QuizConfig {
        QuizConfig(title: "\(code.word) Set", sections: [code], count: 10, seconds: 120)
    }
}

// A soft tinted hero box matching the score's color.
extension View {
    fileprivate func heroBox(_ tint: Color) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20).fill(Theme.surface)
                    RoundedRectangle(cornerRadius: 20).fill(tint.opacity(0.12))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20).stroke(tint.opacity(0.26), lineWidth: 1))
    }
}

#Preview {
    NavigationStack { ScoreDetailView(kind: .readiness) }
        .environmentObject(AppState())
        .environmentObject(ProgressStore())
}
