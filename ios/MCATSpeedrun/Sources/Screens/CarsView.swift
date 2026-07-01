// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// CARS "Author Duel". With AI ON this is an interactive debate: you argue, and
// the AI author defends the claim using ONLY the passage (the named source),
// with a coaching note each turn. With AI OFF it's the classic self-assessed
// flow: answer prompts, reveal model answers, rate yourself against a rubric.
// Mirrors the desktop ts/routes/mcat/cars page.

import SwiftUI

struct CarsView: View {
    @EnvironmentObject var app: AppState
    private let cars = MockData.cars

    // Classic (AI off) state.
    @State private var responses: [String]
    @State private var revealed = false
    @State private var checked: Set<Int> = []
    @State private var finished = false

    // AI debate state.
    private enum Role { case student, author }
    private struct DebateTurn: Identifiable {
        let id = UUID()
        var role: Role
        var content: String
        var critique: String?
        var skill: String?
    }
    @State private var debate: [DebateTurn] = []
    @State private var input = ""
    @State private var busy = false
    @State private var errorText = ""

    init() {
        _responses = State(initialValue: Array(repeating: "", count: MockData.cars.prompts.count))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerRow.screenEnter(delay: 0.02)
                passageCard.screenEnter(delay: 0.08)
                Group {
                    if app.aiEnabled {
                        debateSection
                    } else {
                        classicSection
                    }
                }
                .screenEnter(delay: 0.14)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: revealed)
            .animation(.easeInOut(duration: 0.2), value: finished)
            .animation(.easeInOut(duration: 0.2), value: debate.count)
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
            Pill(text: app.aiEnabled ? "CARS · AI" : "CARS", color: Theme.amber)
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

    // MARK: - AI debate

    private var debateSection: some View {
        VStack(spacing: 14) {
            introCard
            ForEach(debate) { turn in debateBubble(turn) }
            if busy { thinkingBubble }
            if !errorText.isEmpty {
                Text(errorText)
                    .font(Theme.font(14, .semibold))
                    .foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            composer
            if finished {
                finishedCard
            } else {
                Button("Finish debate") {
                    finished = true
                    app.completeActiveLaunch()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(debate.isEmpty)
                .opacity(debate.isEmpty ? 0.5 : 1)
            }
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Debate the author")
                .font(Theme.font(16, .bold))
                .foregroundStyle(Theme.text)
            Text(
                "The author will defend their claim using the passage. Challenge it, "
                    + "defend it, stress-test it — argue in your own words.")
                .font(Theme.font(14))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(tint: Theme.accent)
    }

    private func debateBubble(_ turn: DebateTurn) -> some View {
        let isAuthor = turn.role == .author
        return VStack(alignment: .leading, spacing: 8) {
            Text(isAuthor ? "AUTHOR" : "YOU")
                .font(Theme.font(11, .heavy))
                .foregroundStyle(Theme.muted)
            Text(turn.content)
                .font(Theme.font(15))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let critique = turn.critique, !critique.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Rectangle().fill(Theme.border).frame(height: 1)
                    HStack(alignment: .top, spacing: 8) {
                        Text("COACH")
                            .font(Theme.font(10, .heavy))
                            .foregroundStyle(Theme.accent)
                        Text(critique)
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let skill = turn.skill, !skill.isEmpty {
                        Pill(text: skill, color: Theme.accent)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isAuthor ? Theme.surface : Theme.accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isAuthor ? Theme.border : Theme.accent.opacity(0.26), lineWidth: 1)
        )
    }

    private var thinkingBubble: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("The author is composing a rebuttal…")
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $input)
                .font(Theme.font(15))
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 88)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if input.isEmpty {
                        Text("Make your argument…")
                            .font(Theme.font(15))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 13).padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
            Button(busy ? "Sending…" : "Send argument") { sendDebate() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || input.trimmingCharacters(in: .whitespaces).count < 3)
                .opacity(busy || input.trimmingCharacters(in: .whitespaces).count < 3 ? 0.5 : 1)
        }
    }

    private func sendDebate() {
        let msg = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty, !busy else { return }
        busy = true
        errorText = ""
        debate.append(DebateTurn(role: .student, content: msg))
        input = ""
        let history = debate.map {
            (role: $0.role == .author ? "author" : "student", content: $0.content)
        }
        let passageText = cars.passage
        let claim = cars.authorClaim
        Task {
            let reply = await AIClient.carsDebateReply(
                passage: passageText, authorClaim: claim, history: history, studentMessage: msg)
            await MainActor.run {
                if let r = reply {
                    debate.append(
                        DebateTurn(
                            role: .author, content: r.reply, critique: r.critique, skill: r.skill))
                } else {
                    errorText = "The author is thinking… try again in a moment."
                }
                busy = false
            }
        }
    }

    // MARK: - Classic (AI off)

    private var classicSection: some View {
        VStack(spacing: 16) {
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
    }

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
                Text(app.aiEnabled
                     ? "You traded \(debate.filter { $0.role == .student }.count) arguments with the author."
                     : "You checked \(checked.count) of \(cars.rubric.count) rubric points.")
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
