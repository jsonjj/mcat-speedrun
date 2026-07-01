// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Detail for a single score (Memory / Performance / Readiness): a tinted hero
// with the headline range, what it means, and the evidence behind it.

import SwiftUI

struct ScoreDetailView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var progress: ProgressStore
    var kind: ScoreKind

    var body: some View {
        let block = scoreBlock(for: kind)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard(block)

                Text(kind.means)
                    .font(Theme.font(17, .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)

                factsCard(block)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero

    private func heroCard(_ block: ScoreBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kind.title)
                .font(Theme.font(16, .bold))
                .foregroundStyle(Theme.text)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(block.display)
                    .font(Theme.font(52, .heavy))
                    .foregroundStyle(block.tone.color)
                if kind == .readiness {
                    Text("/ 528")
                        .font(Theme.font(22, .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }

            Text(block.tone.label)
                .font(Theme.font(15, .semibold))
                .foregroundStyle(Theme.muted)
        }
        .cardStyle(tint: block.tone.color)
    }

    // MARK: - Facts

    private func factsCard(_ block: ScoreBlock) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            factRow("How we get it", block.evidence)
            factRow("Coverage", "\(Int(block.coveragePct * 100))%")
            if let point = block.point {
                factRow("Point estimate", pointValue(point, isPercent: block.isPercent))
            }
            factRow("Best next", block.bestNext, bold: true)
        }
        .cardStyle()
    }

    private func factRow(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(Theme.font(15, .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(Theme.font(16, bold ? .bold : .regular))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Data helpers

    private func scoreBlock(for kind: ScoreKind) -> ScoreBlock {
        let model = Scoring.model(app: app, progress: progress)
        switch kind {
        case .memory: return model.memory
        case .performance: return model.performance
        case .readiness: return model.readiness
        }
    }

    private func pointValue(_ point: Double, isPercent: Bool) -> String {
        let rounded = Int(point.rounded())
        return isPercent ? "\(rounded)%" : "\(rounded)"
    }
}

#Preview {
    NavigationStack { ScoreDetailView(kind: .readiness) }
        .environmentObject(AppState())
        .environmentObject(ProgressStore())
}
