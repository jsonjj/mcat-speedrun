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
