// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Dashboard (home): a big adaptive "what to do next" CTA, the three evidence
// scores — each with a small "best next step" link to the exact targeted
// practice — a days-to-exam ring, and the score-estimate card.

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var progress: ProgressStore

    @State private var showMastery = false
    @State private var draft: Double = 80

    private var model: DashboardModel { Scoring.model(app: app, progress: progress) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenHeader("Dashboard", "Three measures, with evidence.")

                togglesRow
                if app.isDev { devMasteryButton }

                ctaLink

                ringSection

                scoreBlock(
                    title: "Memory Recall", icon: ScoreKind.memory.icon,
                    block: model.memory, scaleMin: 0, scaleMax: 100, kind: .memory)
                scoreBlock(
                    title: "Applied Under Exam Conditions",
                    icon: ScoreKind.performance.icon,
                    block: model.performance, scaleMin: 0, scaleMax: 100,
                    kind: .performance)
                scoreBlock(
                    title: "Overall Readiness", icon: ScoreKind.readiness.icon,
                    block: model.readiness, scaleMin: 472, scaleMax: 528,
                    kind: .readiness)

                estimateCard
            }
            .padding(16)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMastery) { masterySheet }
    }

    // MARK: - The big adaptive "what to do next" CTA

    private struct Cta {
        var eyebrow: String
        var title: String
        var sub: String
        var icon: String
        var progress: Double?
        var green: Bool
    }

    private var cta: Cta {
        if !app.diagnosticDone {
            return Cta(
                eyebrow: "Start here", title: "Take your diagnostic",
                sub: "A quick placement test seeds your three scores.",
                icon: "target", progress: nil, green: false)
        }
        if app.allDone {
            return Cta(
                eyebrow: "Today's path is done", title: "Do Extra Practice",
                sub: "Sharpen your weak areas with targeted sets.",
                icon: "sparkles", progress: nil, green: true)
        }
        let total = app.total
        let done = app.doneCount
        return Cta(
            eyebrow: "Start here",
            title: done > 0 ? "Continue Today's Path" : "Start Today's Path",
            sub: total > 0
                ? "\(done) of \(total) blocks done · unlocks Extra Practice"
                : "Your guided plan for today.",
            icon: "target",
            progress: total > 0 ? Double(done) / Double(total) : nil,
            green: false)
    }

    @ViewBuilder private var ctaDestination: some View {
        if !app.diagnosticDone {
            DiagnosticView()
        } else if app.allDone {
            ExtraPracticeView()
        } else {
            RoadmapView()
        }
    }

    private var ctaLink: some View {
        let c = cta
        let base = c.green ? Theme.green : Theme.accent
        return NavigationLink { ctaDestination } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.2))
                    Image(systemName: c.icon).font(Theme.font(22, .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.eyebrow.uppercased())
                        .font(Theme.font(11, .heavy)).tracking(0.5)
                        .foregroundStyle(.white.opacity(0.9))
                    Text(c.title).font(Theme.font(21, .heavy)).foregroundStyle(.white)
                    Text(c.sub).font(Theme.font(13, .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    if let p = c.progress {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.28))
                                Capsule().fill(.white)
                                    .frame(width: max(6, geo.size.width * p))
                            }
                        }
                        .frame(height: 7).padding(.top, 6)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(Theme.font(18, .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [base, base.opacity(0.82)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .buttonStyle(.plain)
        .tapSound()
    }

    // MARK: - Best next step per score (mirrors the desktop dashboard)

    private enum NextDest {
        case flashcards([SectionCode])
        case questions(QuizConfig)
        case breakdown
    }

    private func bestNext(_ kind: ScoreKind) -> (label: String, dest: NextDest) {
        func set(_ code: SectionCode) -> QuizConfig {
            QuizConfig(
                title: "\(code.word) Set", sections: [code], count: 10, seconds: 120)
        }
        switch kind {
        case .memory:
            if let w = Scoring.sectionsRanked(app: app, progress: progress, measure: .memory)
                .first
            {
                return ("\(w.code.word) flashcards", .flashcards([w.code]))
            }
            return ("Start a memory block", .flashcards([.bb, .cp, .ps]))
        case .performance:
            if let w = Scoring.sectionsRanked(
                app: app, progress: progress, measure: .performance
            ).first {
                return ("Timed set — \(w.code.word)", .questions(set(w.code)))
            }
            return (
                "Do a question set",
                .questions(
                    QuizConfig(
                        title: "Mini-MCAT", sections: [.bb, .cp, .ps, .cars], count: 12,
                        seconds: 120))
            )
        case .readiness:
            if model.readiness.abstained {
                return ("Do a review set", .flashcards([.bb, .cp, .ps]))
            }
            if let w = Scoring.sectionsRanked(
                app: app, progress: progress, measure: .performance
            ).first {
                return ("Sharpen \(w.code.word)", .questions(set(w.code)))
            }
            return ("See full breakdown", .breakdown)
        }
    }

    @ViewBuilder private func nextDestView(_ dest: NextDest) -> some View {
        switch dest {
        case .flashcards(let s): FlashcardsView(sections: s)
        case .questions(let c): QuestionRunnerView(config: c)
        case .breakdown: BreakdownView()
        }
    }

    // MARK: - Score card with its best-next step inside the same tinted box

    private func scoreBlock(
        title: String, icon: String, block: ScoreBlock,
        scaleMin: Double, scaleMax: Double, kind: ScoreKind
    ) -> some View {
        let n = bestNext(kind)
        let tint = block.tone.color
        return VStack(spacing: 0) {
            NavigationLink {
                ScoreDetailView(kind: kind)
            } label: {
                cardContent(
                    title: title, icon: icon, block: block,
                    scaleMin: scaleMin, scaleMax: scaleMax)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tapSound()

            NavigationLink {
                nextDestView(n.dest)
            } label: {
                HStack(spacing: 10) {
                    Text("Best next step")
                        .font(Theme.font(11, .heavy)).tracking(0.4)
                        .textCase(.uppercase).foregroundStyle(Theme.muted)
                    Spacer(minLength: 0)
                    Text(n.label).font(Theme.font(15, .heavy)).foregroundStyle(tint)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Image(systemName: "arrow.right").font(Theme.font(13, .bold))
                        .foregroundStyle(tint)
                }
                .padding(.horizontal, 18).padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(0.06))
                .overlay(alignment: .top) {
                    Rectangle().fill(tint.opacity(0.26)).frame(height: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tapSound()
        }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface)
                RoundedRectangle(cornerRadius: Theme.radius).fill(tint.opacity(0.10))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radius)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    @ViewBuilder
    private func cardContent(
        title: String, icon: String, block: ScoreBlock,
        scaleMin: Double, scaleMax: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: icon).foregroundStyle(block.tone.color)
                Text(title).font(Theme.font(17, .bold)).foregroundStyle(Theme.text)
                Spacer()
                if block.isPercent, !block.abstained, let p = block.point {
                    CountUpText(
                        value: p, suffix: "%", font: Theme.font(30, .heavy),
                        color: block.tone.color)
                } else {
                    Text(block.display).font(Theme.font(30, .heavy))
                        .foregroundStyle(block.tone.color)
                }
            }
            RangeBarView(
                lo: scaleMin, hi: scaleMax,
                low: block.low ?? scaleMin, high: block.high ?? scaleMin,
                point: block.point ?? scaleMin, color: block.tone.color)
            HStack(spacing: 6) {
                Circle().fill(block.tone.color).frame(width: 7, height: 7)
                Text(block.abstained ? "Not enough evidence yet" : block.tone.label)
                    .font(Theme.font(13, .semibold)).foregroundStyle(block.tone.color)
            }
        }
    }

    // MARK: - Top toggles (sound + dark mode)

    private var togglesRow: some View {
        HStack(spacing: 10) {
            Spacer()
            ToggleChip(
                icon: app.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                label: "Sound", isOn: $app.soundOn)
            ToggleChip(
                icon: app.darkMode ? "moon.fill" : "sun.max.fill",
                label: "Dark Mode", isOn: $app.darkMode)
        }
    }

    // MARK: - Dev mastery override

    private var devMasteryButton: some View {
        HStack {
            Spacer()
            Button("Set mastery") {
                draft = app.devMastery ?? 80
                showMastery = true
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(width: 160)
        }
    }

    private var masterySheet: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Set Mastery")
                    .font(Theme.font(20, .heavy)).foregroundStyle(Theme.text)
                Text("Overrides the Memory & Performance scores.")
                    .font(Theme.font(14, .semibold)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            Text("\(Int(draft))%").font(Theme.font(46, .heavy)).foregroundStyle(Theme.accent)
            Slider(value: $draft, in: 0...100).tint(Theme.accent)
            VStack(spacing: 10) {
                Button("Apply") {
                    app.devMastery = draft
                    showMastery = false
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Clear override") {
                    app.devMastery = nil
                    showMastery = false
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .screenBackground()
        .presentationDetents([.medium])
    }

    // MARK: - Days ring + streak

    private var ringSection: some View {
        VStack(spacing: 8) {
            DaysRingView(days: app.daysToGo ?? model.daysToGo)
            if app.streak > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                    Text("\(app.streak)-day streak")
                }
                .font(Theme.font(14, .bold)).foregroundStyle(Theme.amber)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Score estimate

    /// Total = sum of the four section ranges once all four have an estimate.
    private var totalRange: (low: Int, high: Int)? {
        let sections = model.sections
        let ready = sections.filter { !$0.abstained }
        guard sections.count == 4, ready.count == 4 else { return nil }
        let low = ready.reduce(0) { $0 + Int($1.low.rounded()) }
        let high = ready.reduce(0) { $0 + Int($1.high.rounded()) }
        return (low, high)
    }

    private var estimateCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Score Estimate")
                    .font(Theme.font(18, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Text(totalRange.map { "\($0.low) – \($0.high)" } ?? "—")
                    .font(Theme.font(26, .heavy)).foregroundStyle(Theme.accent)
            }
            VStack(spacing: 13) {
                ForEach(model.sections) { section in
                    HStack(spacing: 12) {
                        Text(section.code.word)
                            .font(Theme.font(14, .bold)).foregroundStyle(Theme.text)
                            .frame(width: 92, alignment: .leading)
                        RangeBarView(
                            lo: 118, hi: 132,
                            low: section.low, high: section.high, point: section.point,
                            color: section.abstained ? Theme.muted : section.tone.color)
                        Text(
                            section.abstained
                                ? "—" : "\(Int(section.low)) – \(Int(section.high))"
                        )
                        .font(Theme.font(13, .bold)).foregroundStyle(Theme.muted)
                        .frame(width: 78, alignment: .trailing)
                    }
                }
            }
            NavigationLink {
                BreakdownView()
            } label: {
                HStack(spacing: 5) {
                    Text("See Full Breakdown")
                    Image(systemName: "arrow.right")
                }
                .font(Theme.font(14, .bold)).foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .tapSound()
        }
        .cardStyle(tint: Theme.accent)
    }
}

#Preview {
    NavigationStack { DashboardView() }
        .environmentObject(AppState())
        .environmentObject(ProgressStore())
}
