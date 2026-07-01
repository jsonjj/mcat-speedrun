// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Placement diagnostic (mirrors the desktop): pick a length, answer a balanced
// mix across all four sections, and it seeds your Performance so Readiness shows
// a low-confidence estimate. Records real attempts + the diagnostic kind (synced).

import SwiftUI

struct DiagnosticView: View {
    @State private var started = false
    @State private var kind = "standard"
    @State private var items: [Question] = []

    private let options: [(kind: String, title: String, sub: String, per: Int)] = [
        ("quick", "Quick", "3 per section · 12 questions", 3),
        ("standard", "Standard", "5 per section · 20 questions", 5),
        ("best_estimate", "Best estimate", "10 per section · 40 questions", 10),
    ]

    var body: some View {
        Group {
            if started {
                QuestionRunnerView(
                    config: QuizConfig(
                        title: "Diagnostic", sections: SectionCode.allCases,
                        count: items.count, seconds: nil),
                    items: items, diagnosticKind: kind)
            } else {
                picker
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var picker: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenHeader(
                    "Placement Diagnostic",
                    "Answer a balanced mix across all four sections to seed your scores.")

                ForEach(options, id: \.kind) { opt in
                    Button { kind = opt.kind } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(opt.title)
                                    .font(Theme.font(17, .bold))
                                    .foregroundStyle(Theme.text)
                                Text(opt.sub)
                                    .font(Theme.font(13))
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 0)
                            Image(
                                systemName: kind == opt.kind
                                    ? "largecircle.fill.circle" : "circle"
                            )
                            .font(Theme.font(20))
                            .foregroundStyle(kind == opt.kind ? Theme.accent : Theme.muted)
                        }
                        .cardStyle(tint: kind == opt.kind ? Theme.accent : nil)
                    }
                    .buttonStyle(.plain)
                    .tapSound()
                }

                Button("Start diagnostic") {
                    let per = options.first { $0.kind == kind }?.per ?? 5
                    items = buildItems(per)
                    started = true
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
    }

    private func buildItems(_ per: Int) -> [Question] {
        var out: [Question] = []
        for section in SectionCode.allCases {
            out += Array(
                ContentStore.shared.questions(in: [section]).shuffled().prefix(per))
        }
        return out.shuffled()
    }
}
