// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// CARS "Author Duel": read a passage, answer reasoning prompts in your own
// words, then reveal the strongest challenge and defense and self-assess
// against a rubric.

import SwiftUI

struct CarsView: View {
    @EnvironmentObject var app: AppState
    private let cars = MockData.cars
    @State private var responses: [String]
    @State private var revealed = false
    @State private var checked: Set<Int> = []
    @State private var finished = false

    init() {
        _responses = State(initialValue: Array(repeating: "", count: MockData.cars.prompts.count))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerRow
                passageCard

                ForEach(Array(cars.prompts.enumerated()), id: \.element.id) { index, prompt in
                    promptCard(index: index, prompt: prompt)
                }

                if revealed {
                    modelCard(title: "Strongest challenge", text: cars.strongRebuttal,
                              tint: Theme.red, icon: "exclamationmark.bubble.fill")
                    modelCard(title: "Strongest defense", text: cars.strongDefense,
                              tint: Theme.green, icon: "checkmark.seal.fill")
                    rateYourselfCard
                } else {
                    Button("Reveal model answers") { revealed = true }
                        .buttonStyle(SecondaryButtonStyle())
                }

                if finished {
                    finishedCard
                } else {
                    Button("Finish") {
                        finished = true
                        app.completeActiveLaunch()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: revealed)
            .animation(.easeInOut(duration: 0.2), value: finished)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { SoundManager.shared.start("cars") }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.amber).frame(width: 10, height: 10)
            Text("Author Duel")
                .font(Theme.font(18, .bold))
                .foregroundStyle(Theme.text)
            Spacer()
            Pill(text: "CARS", color: Theme.amber)
        }
    }

    // MARK: - Passage

    private var passageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PASSAGE")
                .font(Theme.font(12, .bold))
                .foregroundStyle(Theme.muted)
            Text(cars.passage)
                .font(Theme.font(16))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Theme.border).frame(height: 1).padding(.vertical, 2)
            Text("THE AUTHOR'S CLAIM")
                .font(Theme.font(11, .bold))
                .foregroundStyle(Theme.muted)
            Text(cars.authorClaim)
                .font(Theme.font(15, .semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    // MARK: - Prompts

    private func promptCard(index: Int, prompt: CarsPrompt) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text("Prompt \(index + 1)")
                    .font(Theme.font(12, .bold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Pill(text: prompt.skill, color: Theme.accent)
            }
            Text(prompt.prompt)
                .font(Theme.font(16, .semibold))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            responseEditor(index)
        }
        .cardStyle()
    }

    private func responseEditor(_ index: Int) -> some View {
        TextEditor(text: binding(for: index))
            .font(Theme.font(15))
            .foregroundStyle(Theme.text)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 90)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                if responses[index].isEmpty {
                    Text("Write your response…")
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: - Model answers

    private func modelCard(title: String, text: String, tint: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title)
                    .font(Theme.font(16, .bold))
                    .foregroundStyle(Theme.text)
            }
            Text(text)
                .font(Theme.font(15))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle(tint: tint)
    }

    private var rateYourselfCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rate yourself")
                .font(Theme.font(16, .bold))
                .foregroundStyle(Theme.text)
            ForEach(Array(cars.rubric.enumerated()), id: \.offset) { index, item in
                Button {
                    toggle(index)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: checked.contains(index) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(checked.contains(index) ? Theme.green : Theme.muted)
                        Text(item)
                            .font(Theme.font(15))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }

    // MARK: - Finish

    private var finishedCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Duel complete")
                    .font(Theme.font(16, .bold))
                    .foregroundStyle(Theme.text)
                Text("You checked \(checked.count) of \(cars.rubric.count) rubric points.")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .cardStyle(tint: Theme.green)
    }

    // MARK: - Actions

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { responses.indices.contains(index) ? responses[index] : "" },
            set: { newValue in
                if responses.indices.contains(index) { responses[index] = newValue }
            }
        )
    }

    private func toggle(_ index: Int) {
        if checked.contains(index) {
            checked.remove(index)
        } else {
            checked.insert(index)
        }
    }
}
