// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Full score report: per-section ranges on the 118–132 scale colored by
// evidence strength, plus the 472–528 total and an evidence legend.

import SwiftUI

struct BreakdownView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var progress: ProgressStore

    private var model: DashboardModel { Scoring.model(app: app, progress: progress) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenHeader("Your Score Estimate").screenEnter()

                ForEach(Array(model.sections.enumerated()), id: \.element.id) { i, section in
                    sectionCard(section).screenEnter(delay: 0.05 + Double(i) * 0.06)
                }

                totalCard.screenEnter(delay: 0.3)

                legend.screenEnter(delay: 0.36)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Per-section card

    private func sectionCard(_ section: SectionReadiness) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: section.code.icon)
                    .foregroundStyle(section.tone.color)
                Text(section.code.word)
                    .font(Theme.font(16, .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(section.abstained ? "—" : "\(Int(section.low)) – \(Int(section.high))")
                    .font(Theme.font(24, .heavy))
                    .foregroundStyle(section.abstained ? Theme.muted : section.tone.color)
            }

            VStack(spacing: 6) {
                RangeBarView(
                    lo: 118, hi: 132,
                    low: section.low, high: section.high, point: section.point,
                    color: section.abstained ? Theme.muted : section.tone.color
                )
                HStack {
                    Text("118")
                    Spacer()
                    Text("125")
                    Spacer()
                    Text("132")
                }
                .font(Theme.font(11, .semibold))
                .foregroundStyle(Theme.muted)
            }
        }
        .cardStyle()
    }

    // MARK: - Total

    private var totalCard: some View {
        // The total is simply the sum of the section ranges once all four have an
        // estimate (mirrors the desktop breakdown) — independent of the overall
        // readiness abstention gate.
        let ready = model.sections.filter { !$0.abstained }
        let allReady = model.sections.count == 4 && ready.count == 4
        let low = ready.reduce(0) { $0 + Int($1.low.rounded()) }
        let high = ready.reduce(0) { $0 + Int($1.high.rounded()) }
        let mid = (low + high) / 2

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Total · 472–528 Scale")
                    .font(Theme.font(14, .bold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text(allReady ? "\(low) – \(high)" : "—")
                    .font(Theme.font(28, .heavy))
                    .foregroundStyle(allReady ? Theme.accent : Theme.muted)
            }

            // Always show the range bar + numeric scale (grey stub before all four
            // sections have an estimate), matching the per-section cards.
            VStack(spacing: 6) {
                RangeBarView(
                    lo: 472, hi: 528,
                    low: allReady ? Double(low) : 472,
                    high: allReady ? Double(high) : 472,
                    point: allReady ? Double(mid) : 472,
                    color: allReady ? Theme.accent : Theme.muted
                )
                HStack {
                    Text("472")
                    Spacer()
                    Text("500")
                    Spacer()
                    Text("528")
                }
                .font(Theme.font(11, .semibold))
                .foregroundStyle(Theme.muted)
            }

            if !allReady {
                Text("Complete more study to unlock a total range.")
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .cardStyle(tint: Theme.accent)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 18) {
            legendItem(Theme.green, "Strong")
            legendItem(Theme.amber, "Moderate")
            legendItem(Theme.red, "Thin Evidence")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text)
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.muted)
        }
    }
}

#Preview {
    NavigationStack { BreakdownView() }
        .environmentObject(AppState())
        .environmentObject(ProgressStore())
}
