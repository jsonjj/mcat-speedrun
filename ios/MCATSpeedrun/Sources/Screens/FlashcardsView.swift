// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Spaced Review: an FSRS-style flashcard reviewer over MockData.flashcards.
// Reveal the back, then grade recall (Again/Hard/Good/Easy) to advance.

import Foundation
import SwiftUI

struct FlashcardsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var progress: ProgressStore
    private let sections: [SectionCode]
    private let limit: Int
    @State private var cards: [Flashcard] = []
    @State private var loaded = false
    @State private var idx = 0
    @State private var revealed = false
    @State private var reported = false
    // Recall tally for the roadmap node score (anything but "Again" = recalled).
    @State private var graded = 0
    @State private var recalled = 0
    @State private var doneIn = false

    init(sections: [SectionCode] = SectionCode.allCases, limit: Int = 12) {
        self.sections = sections
        self.limit = limit
    }

    private var isComplete: Bool { loaded && idx >= cards.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !loaded {
                    loadingCard
                } else if isComplete {
                    completeCard
                } else {
                    headerRow
                    flashcardView(cards[idx])
                    controls
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: revealed)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            SoundManager.shared.start("memory")
            if !loaded { loadCards() }
        }
    }

    /// Build the review set with DUE cards first (spaced repetition), asking the
    /// shared engine which cards are due from the merged log — so a card reviewed
    /// on desktop won't resurface here until it's due, and vice-versa.
    private func loadCards() {
        let pool = ContentStore.shared.flashcards(in: sections)
        let allKeys = pool.map { $0.key }
        let allKeysJSON =
            (try? JSONSerialization.data(withJSONObject: allKeys))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let dueJSON = Engine.dueCards(
            state: progress.combinedLogJSON(), allKeys: allKeysJSON,
            nowTs: Int64(Date().timeIntervalSince1970), retention: 0.9)
        var dueSet = Set<String>()
        if let data = dueJSON.data(using: .utf8),
            let keys = try? JSONDecoder().decode([String].self, from: data)
        {
            dueSet = Set(keys)
        }
        let due = pool.filter { dueSet.contains($0.key) }.shuffled()
        let rest = pool.filter { !dueSet.contains($0.key) }.shuffled()
        cards = Array((due + rest).prefix(max(1, limit)))
        loaded = true
    }

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Theme.accent)
            Text("Loading your due cards…")
                .font(Theme.font(15))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220)
        .cardStyle()
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(Theme.green).frame(width: 10, height: 10)
                Text("Spaced Review")
                    .font(Theme.font(18, .bold))
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            Text("Card \(idx + 1) of \(cards.count)")
                .font(Theme.font(14, .semibold))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: - Card (3D flip on reveal)

    private func flashcardView(_ card: Flashcard) -> some View {
        ZStack {
            cardFace(section: card.section, label: "Question",
                     labelColor: Theme.muted, text: card.front, big: true)
                .opacity(revealed ? 0 : 1)
            cardFace(section: nil, label: "Answer",
                     labelColor: Theme.green, text: card.back, big: false)
                .opacity(revealed ? 1 : 0)
                // Pre-counter-rotate so the back reads correctly once flipped.
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(
            .degrees(revealed ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6
        )
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: revealed)
        // Fresh identity per card so advancing eases the next one in.
        .id(idx)
        .transition(
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .opacity))
    }

    private func cardFace(
        section: SectionCode?, label: String, labelColor: Color, text: String, big: Bool
    ) -> some View {
        VStack(spacing: 14) {
            HStack {
                if let section {
                    Pill(text: section.abbr, color: sectionColor(section))
                }
                Spacer()
                Text(label).font(Theme.font(12, .bold)).foregroundStyle(labelColor)
            }
            Spacer(minLength: 12)
            MarkdownContent(
                text: text, size: big ? 22 : 19,
                weight: big ? .bold : .semibold, centered: true)
            Spacer(minLength: 12)
        }
        .frame(minHeight: 340)
        .cardStyle()
    }

    // MARK: - Controls

    @ViewBuilder private var controls: some View {
        if revealed {
            VStack(spacing: 10) {
                Text("How well did you recall it?")
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    Button("Again") { advance(rating: 1) }
                        .buttonStyle(GradeButtonStyle(color: Theme.red))
                    Button("Hard") { advance(rating: 2) }
                        .buttonStyle(GradeButtonStyle(color: Theme.amber))
                    Button("Good") { advance(rating: 3) }
                        .buttonStyle(GradeButtonStyle(color: Theme.green))
                    Button("Easy") { advance(rating: 4) }
                        .buttonStyle(GradeButtonStyle(color: Theme.accent))
                }
            }
        } else {
            Button("Reveal Answer") { revealed = true }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: - Done state

    private var completeCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.green)
                .scaleEffect(doneIn ? 1 : 0.2)
                .opacity(doneIn ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.55), value: doneIn)
                .onAppear { doneIn = true }
            Text("Review complete")
                .font(Theme.font(22, .bold))
                .foregroundStyle(Theme.text)
            Text("You worked through all \(cards.count) cards.")
                .font(Theme.font(15))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button("Start over") {
                idx = 0
                revealed = false
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220)
        .cardStyle()
    }

    // MARK: - Actions & helpers

    private func advance(rating: Int) {
        if idx < cards.count {
            progress.recordReview(
                section: cards[idx].section, cardKey: cards[idx].key, rating: rating)
            graded += 1
            if rating != 1 { recalled += 1 }
        }
        // Reset the flip and ease the next card in as one transaction.
        withAnimation(.easeOut(duration: 0.3)) {
            revealed = false
            idx += 1
        }
        if isComplete && !reported {
            reported = true
            app.completeActiveLaunch(score: BlockScore(correct: recalled, total: graded))
        }
    }

    private func sectionColor(_ code: SectionCode) -> Color {
        switch code {
        case .bb: return Theme.green
        case .cp: return Theme.cyan
        case .ps: return Theme.accent
        case .cars: return Theme.amber
        }
    }
}

/// Filled, rounded FSRS grade button with white text on a solid tone.
private struct GradeButtonStyle: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(15, .bold))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
