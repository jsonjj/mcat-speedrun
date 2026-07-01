// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

struct ExtraPracticeView: View {
    @EnvironmentObject var app: AppState
    @State private var locked = false
    @State private var heroIn = false
    @State private var seal = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if app.allDone {
                    unlockedHeader
                    practiceOptions
                } else {
                    lockedHero
                }
                dailyDiagnosticCard
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
        .screenEnter()
    }

    // MARK: - Locked hero

    private var lockedHero: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.10))
                // Sealed pulse ring — signals it's locked/waiting.
                Circle().stroke(Theme.accent.opacity(0.4), lineWidth: 2)
                    .scaleEffect(seal ? 1.18 : 0.92)
                    .opacity(seal ? 0 : 0.8)
                // Starts open, then clicks shut — a literal "locking" animation.
                Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                    .font(Theme.font(90, .semibold))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 180, height: 180)
            .overlay(Circle().stroke(Theme.accent.opacity(0.24), lineWidth: 1.5))
            .scaleEffect(heroIn ? 1 : 0.7)
            .opacity(heroIn ? 1 : 0)

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
            .screenEnter(delay: 0.5)
        }
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical) { height, _ in height * 0.6 }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { heroIn = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation { locked = true }
                withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                    seal = true
                }
            }
        }
    }

    // MARK: - Practice options

    private var practiceOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                QuestionRunnerView(config: QuizConfig(
                    title: "Mini-MCAT",
                    sections: SectionCode.allCases,
                    count: 12,
                    seconds: 120
                ))
            } label: {
                PracticeOptionRow(
                    icon: "bolt.fill", tint: Theme.accent,
                    title: "Mini-MCAT", subtitle: "12 mixed questions, timed"
                )
            }
            .buttonStyle(.plain)
            .tapSound()
            .screenEnter(delay: 0.05)

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
                .screenEnter(delay: 0.11)
            }

            NavigationLink {
                carsDestination
            } label: {
                PracticeOptionRow(
                    icon: "book.fill", tint: Theme.amber,
                    title: app.aiEnabled ? "CARS Author Duel" : "CARS Practice",
                    subtitle: app.aiEnabled
                        ? "Debate the author (AI)" : "Passage-style MCQ problems"
                )
            }
            .buttonStyle(.plain)
            .tapSound()
            .screenEnter(delay: 0.17)
        }
    }

    /// AI on → interactive Author Duel; AI off → CARS MCQ practice.
    @ViewBuilder private var carsDestination: some View {
        if app.aiEnabled {
            CarsView()
        } else {
            QuestionRunnerView(
                config: QuizConfig(
                    title: "CARS Practice", sections: [.cars], count: 10, seconds: 120))
        }
    }

    // MARK: - Daily diagnostic (once per day, synced; refines scores)

    private var dailyDiagnosticCard: some View {
        VStack(spacing: 12) {
            if app.dailyDiagnosticAvailable {
                VStack(spacing: 4) {
                    Text("Take a daily diagnostic")
                        .font(Theme.font(17, .heavy))
                        .foregroundStyle(Theme.text)
                    Text("One per day — it adds to your scores to sharpen the estimate.")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    diagOption("Quick", "~12 Q", "quick")
                    diagOption("Standard", "~20 Q", "standard")
                    diagOption("Best", "~40 Q", "best_estimate")
                }
            } else {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Theme.green).frame(width: 34, height: 34)
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily diagnostic done")
                            .font(Theme.font(16, .bold))
                            .foregroundStyle(Theme.text)
                        Text("Come back tomorrow — your scores keep refining.")
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle(tint: Theme.accent)
        .screenEnter(delay: 0.12)
    }

    private func diagOption(_ label: String, _ detail: String, _ kind: String)
        -> some View
    {
        NavigationLink {
            DiagnosticView(presetKind: kind)
        } label: {
            VStack(spacing: 3) {
                Text(label).font(Theme.font(15, .bold)).foregroundStyle(Theme.accent)
                Text(detail).font(Theme.font(12, .semibold)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.accent.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .tapSound()
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
