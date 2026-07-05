// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Dashboard tab: the three evidence-first scores, a days-to-exam ring, and a
// compact score-estimate card that links through to the full breakdown.

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var progress: ProgressStore

    @State private var showMastery = false
    @State private var draft: Double = 80
    @State private var infoKind: ScoreKind?

    private var model: DashboardModel { Scoring.model(app: app, progress: progress) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenHeader("Dashboard", "Three measures, with evidence.")

                togglesRow
                if app.isDev { devMasteryButton }
                if !app.diagnosticDone { diagnosticPrompt }

                ringSection

                scoreCard(title: "Memory Recall",
                          icon: ScoreKind.memory.icon,
                          block: model.memory,
                          scaleMin: 0, scaleMax: 100,
                          kind: .memory)
                scoreCard(title: "Applied Under Exam Conditions",
                          icon: ScoreKind.performance.icon,
                          block: model.performance,
                          scaleMin: 0, scaleMax: 100,
                          kind: .performance)
                scoreCard(title: "Overall Readiness",
                          icon: ScoreKind.readiness.icon,
                          block: model.readiness,
                          scaleMin: 472, scaleMax: 528,
                          kind: .readiness)

                estimateCard
            }
            .padding(16)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMastery) { masterySheet }
    }

    // MARK: - Score badges (Weakest / Strongest / Not enough data)

    private struct Badge {
        enum Kind { case weakest, strongest, nodata }
        var kind: Kind
        var label: String
        var text: String
    }

    private func toneRank(_ b: ScoreBlock) -> Int {
        switch b.tone {
        case .green: return 2
        case .amber: return 1
        case .red: return 0
        }
    }

    /// Highlight the weakest/strongest score by evidence strength (matching the
    /// card colors), plus "Not enough data" on abstained ones. The popups name
    /// the subjects behind the decision (strongest) or the specific practice to
    /// do next (weakest). No AI — computed straight from the scores.
    private var badges: [ScoreKind: Badge] {
        var out: [ScoreKind: Badge] = [:]
        let m = model
        if m.readiness.abstained {
            out[.readiness] = Badge(
                kind: .nodata, label: "Not enough data",
                text: "Not enough reviews yet to project a score.")
        }
        var measurable: [(ScoreKind, Int, Double)] = []
        if m.memory.abstained {
            out[.memory] = Badge(
                kind: .nodata, label: "Not enough data",
                text: "Do some flashcards to measure recall.")
        } else {
            measurable.append((.memory, toneRank(m.memory), m.memory.point ?? 0))
        }
        if m.performance.abstained {
            out[.performance] = Badge(
                kind: .nodata, label: "Not enough data",
                text: "Do a question set to measure applied accuracy.")
        } else {
            measurable.append((.performance, toneRank(m.performance), m.performance.point ?? 0))
        }
        if measurable.count == 2 {
            measurable.sort { ($0.1, $0.2) < ($1.1, $1.2) }
            out[measurable[1].0] = strongestBadge(measurable[1].0)
            out[measurable[0].0] = weakestBadge(measurable[0].0)
        }
        return out
    }

    private func measure(for kind: ScoreKind) -> Scoring.Measure {
        kind == .memory ? .memory : .performance
    }

    private func strongestBadge(_ kind: ScoreKind) -> Badge {
        let ranked = Scoring.sectionsRanked(
            app: app, progress: progress, measure: measure(for: kind))
        let top = ranked.suffix(2).reversed().map { $0.code.word }
        let text = top.isEmpty
            ? "Your strongest area so far."
            : "Strongest: " + top.joined(separator: ", ") + "."
        return Badge(kind: .strongest, label: "Strongest", text: text)
    }

    private func weakestBadge(_ kind: ScoreKind) -> Badge {
        let ranked = Scoring.sectionsRanked(
            app: app, progress: progress, measure: measure(for: kind))
        guard let weak = ranked.first else {
            return Badge(
                kind: .weakest, label: "Weakest",
                text: "Your weakest area — study here next.")
        }
        let name = weak.code.word
        let practice = kind == .memory ? "\(name) flashcards" : "\(name) problems"
        let text = app.allDone
            ? "Weakest: \(name). Practice \(practice) next."
            : "Weakest: \(name). Finish today's path to unlock practice."
        return Badge(kind: .weakest, label: "Weakest", text: text)
    }

    private func badgeColor(_ k: Badge.Kind) -> Color {
        switch k {
        case .weakest: return Theme.red
        case .strongest: return Theme.green
        case .nodata: return Theme.muted
        }
    }

    private func infoBinding(_ k: ScoreKind) -> Binding<Bool> {
        Binding(get: { infoKind == k }, set: { infoKind = $0 ? k : nil })
    }

    @ViewBuilder
    private func badgeView(_ kind: ScoreKind) -> some View {
        if let b = badges[kind] {
            Button { infoKind = kind } label: {
                HStack(spacing: 5) {
                    Text(b.label).font(Theme.font(11, .heavy))
                    Image(systemName: "info.circle.fill").font(.system(size: 11))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(badgeColor(b.kind)))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .offset(x: 12, y: -10)
            .popover(isPresented: infoBinding(kind)) {
                Text(b.text)
                    .font(Theme.font(14, .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(14)
                    .frame(width: 240)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    // MARK: - Top toggles (sound + dark mode)

    private var togglesRow: some View {
        HStack(spacing: 10) {
            Spacer()
            ToggleChip(
                icon: app.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                label: "Sound",
                isOn: $app.soundOn
            )
            ToggleChip(
                icon: app.darkMode ? "moon.fill" : "sun.max.fill",
                label: "Dark Mode",
                isOn: $app.darkMode
            )
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
                    .font(Theme.font(20, .heavy))
                    .foregroundStyle(Theme.text)
                Text("Overrides the Memory & Performance scores.")
                    .font(Theme.font(14, .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }

            Text("\(Int(draft))%")
                .font(Theme.font(46, .heavy))
                .foregroundStyle(Theme.accent)

            Slider(value: $draft, in: 0...100)
                .tint(Theme.accent)

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

    // MARK: - Diagnostic prompt

    private var diagnosticPrompt: some View {
        NavigationLink {
            DiagnosticView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "target")
                    .font(Theme.font(20, .bold))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Take your placement diagnostic")
                        .font(Theme.font(16, .bold))
                        .foregroundStyle(Theme.text)
                    Text("Seed your scores with a quick mixed set.")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(Theme.font(13, .bold))
                    .foregroundStyle(Theme.muted)
            }
            .cardStyle(tint: Theme.accent)
        }
        .buttonStyle(.plain)
        .tapSound()
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
                .font(Theme.font(14, .bold))
                .foregroundStyle(Theme.amber)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tappable evidence card

    private func scoreCard(
        title: String,
        icon: String,
        block: ScoreBlock,
        scaleMin: Double,
        scaleMax: Double,
        kind: ScoreKind
    ) -> some View {
        NavigationLink {
            ScoreDetailView(kind: kind)
        } label: {
            EvidenceCardView(
                title: title,
                icon: icon,
                block: block,
                scaleMin: scaleMin,
                scaleMax: scaleMax
            )
        }
        .buttonStyle(.plain)
        .tapSound()
        .overlay(alignment: .topLeading) { badgeView(kind) }
    }

    // MARK: - Score estimate

    private var estimateCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Score Estimate")
                    .font(Theme.font(18, .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(model.readiness.abstained ? "—" : "\(model.estLow) – \(model.estHigh)")
                    .font(Theme.font(26, .heavy))
                    .foregroundStyle(Theme.accent)
            }

            VStack(spacing: 13) {
                ForEach(model.sections) { section in
                    HStack(spacing: 12) {
                        Text(section.code.word)
                            .font(Theme.font(14, .bold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 92, alignment: .leading)
                        RangeBarView(
                            lo: 118, hi: 132,
                            low: section.low, high: section.high, point: section.point,
                            color: section.abstained ? Theme.muted : section.tone.color
                        )
                        Text(section.abstained
                             ? "—"
                             : "\(Int(section.low)) – \(Int(section.high))")
                            .font(Theme.font(13, .bold))
                            .foregroundStyle(Theme.muted)
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
                .font(Theme.font(14, .bold))
                .foregroundStyle(Theme.accent)
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
