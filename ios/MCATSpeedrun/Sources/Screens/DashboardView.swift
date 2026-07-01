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
    @State private var coach: CoachRecommendation?
    @State private var coachLoading = false

    private var model: DashboardModel { Scoring.model(app: app, progress: progress) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenHeader("Dashboard", "Three measures, with evidence.")

                togglesRow
                if app.isDev { devMasteryButton }
                if !app.diagnosticDone { diagnosticPrompt }
                if let coach { coachCard(coach) }

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
        .onAppear { loadCoachIfNeeded() }
        .onChange(of: app.aiEnabled) { _, _ in
            coach = nil
            loadCoachIfNeeded()
        }
    }

    // MARK: - AI study coach

    private func coachCard(_ rec: CoachRecommendation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(
                    LinearGradient(
                        colors: [Theme.accent, Theme.accent2],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "target")
                    .font(Theme.font(18, .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("YOUR AI COACH")
                        .font(Theme.font(11, .heavy))
                        .foregroundStyle(Theme.accent)
                    if let word = sectionWord(rec.section) {
                        Pill(text: word, color: Theme.muted)
                    }
                }
                if !rec.headline.isEmpty {
                    Text(rec.headline)
                        .font(Theme.font(17, .bold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !rec.detail.isEmpty {
                    Text(rec.detail)
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Source: \(rec.source)")
                    .font(Theme.font(12)).italic()
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .cardStyle(tint: Theme.accent)
    }

    private func sectionWord(_ code: String) -> String? {
        SectionCode(rawValue: code)?.word
    }

    /// Fetch the coach when AI is on, a key is present, and there's evidence to
    /// coach on. Fail-safe + non-blocking: any failure leaves the card hidden.
    private func loadCoachIfNeeded() {
        guard app.aiEnabled, AIClient.available,
            Scoring.hasEvidence(app: app, progress: progress)
        else {
            coach = nil
            return
        }
        guard !coachLoading else { return }
        coachLoading = true
        let facts = Scoring.coachFactsJSON(app: app, progress: progress)
        Task {
            let rec = await AIClient.coachRecommendation(factsJSON: facts)
            await MainActor.run {
                coach = rec
                coachLoading = false
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
