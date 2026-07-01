// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// MCAT-style question runner with delayed feedback (mirrors the desktop web
// engine): a first pass with a required confidence label and per-item
// countdown, then — if any first answers were wrong — a second pass over every
// item ("Take Another Look") before answers are revealed. Grading happens
// on-device from each question's `correct` index, since the iOS build is offline.

import SwiftUI

struct QuestionRunnerView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var progress: ProgressStore
    @Environment(\.dismiss) private var dismiss
    let config: QuizConfig

    /// Working set of questions for this run.
    private let items: [Question]
    /// When set (diagnostic run), completion records this as the diagnostic kind.
    private let diagnosticKind: String?

    private enum Stage { case first, feedback, second, results }

    @State private var stage: Stage = .first
    @State private var idx = 0
    @State private var selected: Int? = nil
    @State private var confidence: ConfidenceLevel? = nil
    // Answers are keyed by position in `items` (questions may repeat).
    @State private var firstChoices: [Int: Int] = [:]
    @State private var secondChoices: [Int: Int] = [:]
    @State private var didSecondPass = false
    @State private var timeLeft: Int
    @State private var reported = false
    @State private var recorded = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(config: QuizConfig) {
        self.config = config
        _timeLeft = State(initialValue: config.seconds ?? 0)
        // Real questions from the bundled content pack, filtered to the block's
        // section(s). Never repeat a question within a block (mirrors the desktop,
        // which samples unique note ids): sample a unique, shuffled slice.
        let pool = ContentStore.shared.questions(in: config.sections)
        items = Array(pool.shuffled().prefix(max(1, config.count)))
        diagnosticKind = nil
    }

    /// Diagnostic run: explicit per-section question set; records `kind` on finish.
    init(config: QuizConfig, items: [Question], diagnosticKind: String) {
        self.config = config
        _timeLeft = State(initialValue: config.seconds ?? 0)
        self.items = items
        self.diagnosticKind = diagnosticKind
    }

    private var total: Int { items.count }

    private var wrongFirst: [Int] {
        items.indices.filter { firstChoices[$0] != items[$0].correct }
    }

    private var firstCorrectCount: Int {
        items.indices.filter { firstChoices[$0] == items[$0].correct }.count
    }

    /// How many second-pass answers differ from the first pass so far.
    private var changedCount: Int {
        items.indices.reduce(0) { acc, i in
            let sec = (i == idx && stage == .second) ? selected : secondChoices[i]
            return acc + ((sec != nil && sec != firstChoices[i]) ? 1 : 0)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if items.isEmpty {
                    emptyCard
                } else {
                    switch stage {
                    case .first, .second:
                        header
                        progressBar
                        if stage == .second { secondPassBanner }
                        questionCard(items[idx])
                        choicesView(items[idx])
                        if stage == .first {
                            confidenceSelector
                        } else {
                            Text("Second pass — take another look and lock in your final answer.")
                                .font(Theme.font(14, .semibold))
                                .foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        submitButton
                    case .feedback:
                        feedbackCard
                    case .results:
                        resultsView
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: idx)
            .animation(.easeInOut(duration: 0.2), value: stage)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            SoundManager.shared.start("performance")
            if items.isEmpty { reportComplete() }
        }
        .onReceive(timer) { _ in
            guard config.seconds != nil, stage == .first || stage == .second,
                timeLeft > 0
            else { return }
            timeLeft -= 1
        }
    }

    // MARK: - Header + progress

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accent).frame(width: 10, height: 10)
                Text(config.title)
                    .font(Theme.font(18, .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
            Spacer()
            if config.seconds != nil {
                let low = timeLeft <= 10
                Text(mmss(timeLeft))
                    .font(Theme.font(15, .heavy))
                    .monospacedDigit()
                    .foregroundStyle(low ? Theme.red : Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill((low ? Theme.red : Theme.accent).opacity(0.14)))
            }
        }
    }

    private var progressBar: some View {
        let frac = total > 0 ? CGFloat(idx) / CGFloat(total) : 0
        return VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(Theme.accent)
                        .frame(width: max(0, geo.size.width * frac))
                }
            }
            .frame(height: 8)
            Text("Question \(idx + 1) of \(total)")
                .font(Theme.font(12, .semibold))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var secondPassBanner: some View {
        HStack(spacing: 12) {
            bannerStat("\(wrongFirst.count)", "to fix from pass 1", tint: Theme.red)
            Divider().frame(height: 34)
            bannerStat("\(changedCount)", "answers changed", tint: Theme.accent)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private func bannerStat(_ num: String, _ label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(num).font(Theme.font(24, .heavy)).foregroundStyle(tint)
            Text(label).font(Theme.font(12, .semibold)).foregroundStyle(Theme.muted)
        }
    }

    // MARK: - Question + choices

    private func questionCard(_ q: Question) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Pill(text: q.section.abbr, color: sectionColor(q.section))
            Text(q.stem)
                .font(Theme.font(18, .semibold))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private func choicesView(_ q: Question) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(q.choices.enumerated()), id: \.element.id) { index, choice in
                choiceRow(choice, index: index)
            }
        }
    }

    private func choiceRow(_ choice: Choice, index: Int) -> some View {
        let isSel = selected == index
        let isFirstPick = stage == .second && firstChoices[idx] == index
        return Button {
            selected = index
        } label: {
            HStack(spacing: 12) {
                Text(choice.letter)
                    .font(Theme.font(14, .bold))
                    .foregroundStyle(isSel ? .white : Theme.text)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(isSel ? Theme.accent : Theme.surface2))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSel ? Theme.accent : Theme.border, lineWidth: 1))
                Text(choice.text)
                    .font(Theme.font(16))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if isFirstPick {
                    Text("First pick")
                        .font(Theme.font(11, .bold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.surface2))
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(isSel ? Theme.accent.opacity(0.08) : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSel ? Theme.accent : Theme.border, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Confidence

    private var confidenceSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How confident are you?")
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                ForEach(ConfidenceLevel.allCases) { level in
                    let on = confidence == level
                    Button {
                        confidence = level
                    } label: {
                        Text(level.label)
                            .font(Theme.font(14, .bold))
                            .foregroundStyle(on ? Theme.accent : Theme.text)
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 10).fill(on ? Theme.accent.opacity(0.12) : Theme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.accent : Theme.border, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Submit

    private var submitButton: some View {
        let ready = selected != nil && (stage == .first ? confidence != nil : true)
        let isLast = idx + 1 >= total
        return Button(isLast ? "Submit Response" : "Submit & Next") {
            stage == .first ? submitFirst() : submitSecond()
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!ready)
        .opacity(ready ? 1 : 0.5)
    }

    // MARK: - Feedback (between passes)

    private var feedbackCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text("One more pass before the answers")
                .font(Theme.font(20, .bold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text(
                "\(wrongFirst.count) of your first answers "
                    + "\(wrongFirst.count == 1 ? "looks" : "look") shaky. "
                    + "Take another look and lock in your final choices before the reveal."
            )
            .font(Theme.font(15))
            .foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
            Button("Take Another Look") { startSecond() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                Text("Results").font(Theme.font(20, .bold)).foregroundStyle(Theme.text)
                Text("First-answer correct: \(firstCorrectCount)/\(total)")
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .cardStyle()

            ForEach(items.indices, id: \.self) { i in
                resultCard(i)
            }

            Button("Done") {
                reportComplete()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func resultCard(_ i: Int) -> some View {
        let q = items[i]
        let firstOK = firstChoices[i] == q.correct
        let secondOK = secondChoices[i] == q.correct
        let correctLetter = q.choices.indices.contains(q.correct) ? q.choices[q.correct].letter : "?"
        return VStack(alignment: .leading, spacing: 10) {
            Text(q.stem)
                .font(Theme.font(16, .semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                resultPill("first: \(firstOK ? "correct" : "missed")", ok: firstOK)
                if didSecondPass {
                    resultPill("second: \(secondOK ? "correct" : "missed")", ok: secondOK)
                }
                resultPill("answer: \(correctLetter)", ok: nil)
            }
            if !q.explanation.isEmpty {
                Text(q.explanation)
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func resultPill(_ text: String, ok: Bool?) -> some View {
        let color: Color = ok == nil ? Theme.muted : (ok! ? Theme.green : Theme.red)
        return Text(text)
            .font(Theme.font(12, .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private var emptyCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.green)
            Text("No questions available")
                .font(Theme.font(20, .bold))
                .foregroundStyle(Theme.text)
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 200)
        .cardStyle()
    }

    // MARK: - Actions

    private func submitFirst() {
        firstChoices[idx] = selected
        if idx + 1 < total {
            idx += 1
            selected = nil
            confidence = nil
            resetTimer()
        } else {
            finishFirstPass()
        }
    }

    private func finishFirstPass() {
        if wrongFirst.isEmpty {
            didSecondPass = false
            goResults()
        } else {
            stage = .feedback
        }
    }

    private func startSecond() {
        didSecondPass = true
        secondChoices = firstChoices
        idx = 0
        selected = firstChoices[0]
        stage = .second
        resetTimer()
    }

    private func submitSecond() {
        secondChoices[idx] = selected
        if idx + 1 < total {
            idx += 1
            selected = secondChoices[idx]
            resetTimer()
        } else {
            goResults()
        }
    }

    private func goResults() {
        recordAttempts()
        stage = .results
        reportComplete()
    }

    /// Record first-answer correctness for this batch so the dashboard's
    /// Performance/Readiness scores reflect real work (mirrors the desktop).
    private func recordAttempts() {
        guard !recorded else { return }
        recorded = true
        let batch = items.indices.map { i in
            (
                section: items[i].section, questionKey: items[i].key,
                correct: firstChoices[i] == items[i].correct
            )
        }
        progress.recordBatch(batch)
        if let diagnosticKind { app.diagnosticKind = diagnosticKind }
    }

    private func reportComplete() {
        guard !reported else { return }
        reported = true
        app.completeActiveLaunch()
    }

    private func resetTimer() {
        timeLeft = config.seconds ?? 0
    }

    private func mmss(_ s: Int) -> String {
        let m = s / 60
        let sec = s % 60
        return "\(m):\(sec < 10 ? "0" : "")\(sec)"
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
