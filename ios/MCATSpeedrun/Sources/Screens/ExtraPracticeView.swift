// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

struct ExtraPracticeView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if app.allDone {
                    unlockedHeader
                    practiceOptions
                } else {
                    lockedHero
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Unlocked header

    private var unlockedHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.green.opacity(0.14))
                Image(systemName: "checkmark.seal.fill")
                    .font(Theme.font(22, .bold))
                    .foregroundStyle(Theme.green)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text("Extra Practice unlocked")
                    .font(Theme.font(22, .heavy))
                    .foregroundStyle(Theme.text)
                Text("Today's path is done — drill anything you like.")
                    .font(Theme.font(14, .semibold))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Locked hero

    private var lockedHero: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.10))
                Image(systemName: "lock.fill")
                    .font(Theme.font(90, .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 180, height: 180)
            .overlay(Circle().stroke(Theme.accent.opacity(0.24), lineWidth: 1.5))

            VStack(spacing: 10) {
                Text("Finish Today's Path To Unlock")
                    .font(Theme.font(24, .heavy))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                Text("Extra Practice opens once today's plan is done. Complete your daily blocks, then drill anything you like.")
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical) { height, _ in height * 0.6 }
    }

    // MARK: - Practice options

    private var practiceOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                QuestionRunnerView(config: QuizConfig(
                    title: "Mini-MCAT",
                    sections: SectionCode.allCases,
                    count: 12,
                    seconds: 90
                ))
            } label: {
                PracticeOptionRow(
                    icon: "bolt.fill", tint: Theme.accent,
                    title: "Mini-MCAT", subtitle: "12 mixed questions, timed"
                )
            }
            .buttonStyle(.plain)
            .tapSound()

            // Flashcards are disabled in the final stretch (test-simulation focus).
            if app.phase != "final" {
                NavigationLink {
                    FlashcardsView(sections: SectionCode.allCases)
                } label: {
                    PracticeOptionRow(
                        icon: "rectangle.stack.fill", tint: Theme.cyan,
                        title: "Flashcards", subtitle: "Spaced-recall review"
                    )
                }
                .buttonStyle(.plain)
                .tapSound()
            }

            NavigationLink {
                QuestionRunnerView(config: QuizConfig(
                    title: "CARS Practice",
                    sections: [.cars],
                    count: 10,
                    seconds: 90
                ))
            } label: {
                PracticeOptionRow(
                    icon: "book.fill", tint: Theme.amber,
                    title: "CARS Practice", subtitle: "Passage-style MCQ problems"
                )
            }
            .buttonStyle(.plain)
            .tapSound()
        }
    }
}

// MARK: - Option row

private struct PracticeOptionRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.14))
                Image(systemName: icon)
                    .font(Theme.font(20, .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.font(16, .bold)).foregroundStyle(Theme.text)
                Text(subtitle).font(Theme.font(13, .semibold)).foregroundStyle(Theme.muted)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(Theme.font(14, .bold))
                .foregroundStyle(Theme.muted)
        }
        .cardStyle()
    }
}
