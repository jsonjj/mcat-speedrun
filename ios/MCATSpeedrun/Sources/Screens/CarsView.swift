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

    @Environment(\.dismiss) private var dismiss

    // AI debate state: 4 rounds, one aspect each; win 3 of 4 to clear.
    private enum RStatus { case locked, active, won, lost }
    private enum DebStage { case overview, round, review }
    private struct DebateRound: Identifiable {
        let id = UUID()
        let aspectKey: String
        let aspectLabel: String
        var status: RStatus
        var rivalClaim = ""
        var argument = ""
        var reply = ""
        var note = ""
    }
    @State private var rounds: [DebateRound] = []
    @State private var debStage: DebStage = .overview
    @State private var activeIdx = 0
    @State private var input = ""
    @State private var busy = false
    @State private var judged = false
    @State private var review: (didWell: [String], workOn: [String])?

    private let rivalColor = Color(red: 0.886, green: 0.286, blue: 0.184)

    init() {
        _responses = State(initialValue: Array(repeating: "", count: MockData.cars.prompts.count))
    }

    private var wonCount: Int { rounds.filter { $0.status == .won }.count }
    private var decided: Int {
        rounds.filter { $0.status == .won || $0.status == .lost }.count
    }
    private var cleared: Bool { wonCount >= 3 }

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
            .animation(.easeInOut(duration: 0.2), value: activeIdx)
            .animation(.easeInOut(duration: 0.2), value: judged)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            SoundManager.shared.start("cars")
            if app.aiEnabled && rounds.isEmpty { initRounds() }
        }
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
            MarkdownContent(text: cars.passage, size: 16)
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

    // MARK: - AI debate (round-based)

    @ViewBuilder
    private var debateSection: some View {
        switch debStage {
        case .overview: overviewView
        case .round: roundView
        case .review: reviewView
        }
    }

    private var overviewView: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Debate this passage")
                    .font(Theme.font(20, .bold)).foregroundStyle(Theme.text)
                Text("\(rounds.count) rounds · one aspect each")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(rounds.enumerated()), id: \.element.id) { i, r in
                    Button { enterRound(i) } label: { roundRow(r, i) }
                        .buttonStyle(.plain)
                        .disabled(r.status == .locked)
                }
                Text("Win 3 of 4 to clear the passage")
                    .font(Theme.font(13, .bold)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
            }
            .cardStyle()
            Button(decided > 0 ? "Continue" : "Start debate") { enterActive() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func roundRow(_ r: DebateRound, _ i: Int) -> some View {
        HStack(spacing: 12) {
            Circle().fill(statusColor(r).opacity(0.22))
                .overlay(Circle().stroke(statusColor(r), lineWidth: 1))
                .frame(width: 26, height: 26)
            Text(r.aspectLabel).font(Theme.font(16, .bold)).foregroundStyle(Theme.text)
            Spacer()
            Text(statusLabel(r, i)).font(Theme.font(13, .bold))
                .foregroundStyle(statusColor(r))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    r.status == .active ? Theme.accent : Theme.border,
                    lineWidth: r.status == .active ? 2 : 1)
        )
        .opacity(r.status == .locked ? 0.55 : 1)
    }

    private var roundView: some View {
        let r = rounds[activeIdx]
        return VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(Array(rounds.enumerated()), id: \.element.id) { i, rr in
                    Capsule().fill(segColor(rr.status)).frame(height: 8)
                        .overlay(
                            i == activeIdx
                                ? Capsule().stroke(Theme.accent, lineWidth: 2) : nil)
                }
            }
            HStack {
                Text("Arguing: \(r.aspectLabel)")
                    .font(Theme.font(18, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Text("Round \(activeIdx + 1) of \(rounds.count)")
                    .font(Theme.font(13, .bold)).foregroundStyle(Theme.muted)
            }

            VStack(spacing: 14) {
                if !r.rivalClaim.isEmpty {
                    rivalBubble(r.rivalClaim)
                } else if busy {
                    rivalBubble("…")
                }
                if !r.argument.isEmpty { youBubble(r.argument) }
                if judged && !r.reply.isEmpty { rivalBubble(r.reply) }
            }

            if judged {
                HStack(spacing: 6) {
                    Text(r.status == .won ? "You won this round" : "Rival won this round")
                        .font(Theme.font(15, .heavy))
                        .foregroundStyle(r.status == .won ? Theme.green : Theme.red)
                    if !r.note.isEmpty {
                        Text("· \(r.note)").font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                Button(decided >= rounds.count ? "See results" : "Continue") {
                    continueRound()
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                composer
            }
            Button("← All rounds") { debStage = .overview }
                .font(Theme.font(13, .bold)).foregroundStyle(Theme.muted).buttonStyle(.plain)
        }
    }

    private func rivalBubble(_ text: String) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            MascotView(size: 40, mood: .neutral, color: rivalColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("RIVAL").font(Theme.font(10, .heavy)).foregroundStyle(rivalColor)
                Text(text).font(Theme.font(15)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(rivalColor.opacity(0.12)))
            Spacer(minLength: 20)
        }
    }

    private func youBubble(_ text: String) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            Spacer(minLength: 20)
            VStack(alignment: .trailing, spacing: 4) {
                Text("YOU").font(Theme.font(10, .heavy)).foregroundStyle(.white.opacity(0.85))
                Text(text).font(Theme.font(15)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.accent))
            MascotView(size: 40)
        }
    }

    private var reviewView: some View {
        VStack(spacing: 12) {
            MascotView(size: 80, mood: cleared ? .happy : .neutral)
            Text("Won \(wonCount) of \(rounds.count)")
                .font(Theme.font(24, .heavy)).foregroundStyle(Theme.text)
            Text(cleared ? "Passage cleared" : "Not cleared — win 3 of 4")
                .font(Theme.font(15)).foregroundStyle(Theme.muted)
            if let rev = review {
                if !rev.didWell.isEmpty {
                    slipCard(title: "Did well", items: rev.didWell, tint: Theme.green)
                }
                if !rev.workOn.isEmpty {
                    slipCard(title: "Work on", items: rev.workOn, tint: Theme.amber)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Your coach is reviewing…")
                        .font(Theme.font(13, .semibold)).foregroundStyle(Theme.muted)
                }
            }
            HStack(spacing: 10) {
                Button("Replay") { initRounds() }.buttonStyle(SecondaryButtonStyle())
                Button("Done") {
                    app.completeActiveLaunch()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func slipCard(title: String, items: [String], tint: Color) -> some View {
        VStack(spacing: 12) {
            Text(title).font(Theme.font(14, .heavy)).foregroundStyle(tint)
                .textCase(.uppercase)
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                if idx > 0 { Divider() }
                Text(item).font(Theme.font(18)).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle(tint: tint)
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
                        Text("Rebut the rival in your own words…")
                            .font(Theme.font(15))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 13).padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
            Button(busy ? "Sending…" : "Send") { submitRound() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || input.trimmingCharacters(in: .whitespaces).count < 3)
                .opacity(busy || input.trimmingCharacters(in: .whitespaces).count < 3 ? 0.5 : 1)
        }
    }

    // MARK: - Round helpers + actions

    private func statusColor(_ r: DebateRound) -> Color {
        switch r.status {
        case .won: return Theme.green
        case .lost: return Theme.red
        case .active: return Theme.accent
        case .locked: return Theme.muted
        }
    }
    private func segColor(_ s: RStatus) -> Color {
        switch s {
        case .won: return Theme.green
        case .lost: return Theme.red
        case .active: return Theme.accent
        case .locked: return Theme.track
        }
    }
    private func statusLabel(_ r: DebateRound, _ i: Int) -> String {
        switch r.status {
        case .won: return "You won"
        case .lost: return "Rival won"
        case .active: return "In progress"
        case .locked:
            return rounds.firstIndex(where: { $0.status == .locked }) == i
                ? "Up next" : "Locked"
        }
    }

    private func initRounds() {
        rounds = AIClient.carsAspects.enumerated().map { i, a in
            DebateRound(
                aspectKey: a.key, aspectLabel: a.label, status: i == 0 ? .active : .locked)
        }
        debStage = .overview
        activeIdx = 0
        judged = false
        review = nil
    }

    private func enterActive() {
        enterRound(rounds.firstIndex(where: { $0.status == .active }) ?? 0)
    }

    private func enterRound(_ i: Int) {
        guard rounds.indices.contains(i), rounds[i].status != .locked else { return }
        activeIdx = i
        judged = rounds[i].status == .won || rounds[i].status == .lost
        input = ""
        debStage = .round
        if rounds[i].rivalClaim.isEmpty {
            busy = true
            let passage = cars.passage
            let claim = cars.authorClaim
            let label = rounds[i].aspectLabel
            Task {
                let text = await AIClient.carsRoundOpen(
                    passage: passage, authorClaim: claim, aspectLabel: label)
                await MainActor.run {
                    if rounds.indices.contains(i) {
                        rounds[i].rivalClaim =
                            text
                            ?? "My reading of this aspect is the strongest — prove otherwise."
                    }
                    busy = false
                }
            }
        }
    }

    private func submitRound() {
        let msg = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty, !busy, !judged else { return }
        busy = true
        let i = activeIdx
        rounds[i].argument = msg
        input = ""
        let passage = cars.passage
        let label = rounds[i].aspectLabel
        let claim = rounds[i].rivalClaim
        Task {
            let result = await AIClient.carsRoundJudge(
                passage: passage, aspectLabel: label, rivalClaim: claim, argument: msg)
            await MainActor.run {
                if rounds.indices.contains(i) {
                    rounds[i].reply = result?.reply ?? "The author holds their ground."
                    rounds[i].note = result?.note ?? ""
                    rounds[i].status = (result?.won ?? false) ? .won : .lost
                }
                judged = true
                busy = false
            }
        }
    }

    private func continueRound() {
        if let next = rounds.firstIndex(where: { $0.status == .locked }) {
            rounds[next].status = .active
        }
        if decided >= rounds.count {
            goReview()
        } else {
            debStage = .overview
        }
    }

    private func goReview() {
        debStage = .review
        review = nil
        let passage = cars.passage
        let summary = rounds.map {
            (aspect: $0.aspectLabel, won: $0.status == .won, argument: $0.argument)
        }
        Task {
            let rev = await AIClient.carsReview(passage: passage, rounds: summary)
            await MainActor.run { review = rev }
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
