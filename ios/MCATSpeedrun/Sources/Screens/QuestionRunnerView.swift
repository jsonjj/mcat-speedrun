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
    // AI (second-pass reasoning grading), keyed by position in `items`.
    @State private var reasoning: [Int: String] = [:]
    @State private var aiFeedback: [Int: AiFeedback] = [:]
    @State private var aiGrading = false
    // Drives the results check-pop + staggered result cards.
    @State private var celebrate = false
    // Overtime pulse, pacing tally (questions past the limit), and review paging.
    @State private var pulse = false
    @State private var slowCount = 0
    @State private var reviewPage = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// AI reasoning is active for normal runs when the user has AI on. Diagnostics
    /// stay quick and API-free (placement only), matching the desktop.
    private var aiActive: Bool { app.aiEnabled && diagnosticKind == nil }

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
                        VStack(spacing: 16) {
                            questionCard(items[idx])
                            choicesView(items[idx])
                        }
                        .id(idx)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity))
                        if stage == .first {
                            confidenceSelector
                        } else if aiActive {
                            reasoningInput
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
            // Count into overtime (negative); we never auto-skip a question.
            guard config.seconds != nil, stage == .first || stage == .second
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
                timerPill
            }
        }
    }

    /// Countdown pill. Past the limit it shines red and pulses (never auto-skips).
    private var timerPill: some View {
        let over = timeLeft < 0
        let warn = !over && timeLeft <= 10
        let tint: Color = (over || warn) ? Theme.red : Theme.accent
        return HStack(spacing: 5) {
            if over { Text("OVER").font(Theme.font(10, .heavy)) }
            Text(mmss(timeLeft)).font(Theme.font(15, .heavy)).monospacedDigit()
        }
        .foregroundStyle(over ? .white : tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(over ? Theme.red : tint.opacity(0.14)))
        .scaleEffect(over && pulse ? 1.06 : 1.0)
        .onChange(of: over) { _, isOver in
            if isOver {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
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

    // MARK: - Reasoning (second pass, AI on)

    private func reasoningBinding(_ i: Int) -> Binding<String> {
        Binding(get: { reasoning[i] ?? "" }, set: { reasoning[i] = $0 })
    }

    private var reasoningInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Argue your answer — why is it right?")
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.muted)
            TextEditor(text: reasoningBinding(idx))
                .font(Theme.font(15))
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 88)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if (reasoning[idx] ?? "").isEmpty {
                        Text("Explain your reasoning. Your coach will respond to this.")
                            .font(Theme.font(15))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 13).padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Submit

    private var submitButton: some View {
        let secondReady =
            !aiActive || (reasoning[idx]?.trimmingCharacters(in: .whitespaces).count ?? 0) >= 3
        let ready = selected != nil && (stage == .first ? confidence != nil : secondReady)
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

    private var pageCount: Int { max(1, (total + 4) / 5) }
    private var pageStart: Int { reviewPage * 5 }
    private var pageEnd: Int { min(pageStart + 5, total) }

    private var resultsView: some View {
        VStack(spacing: 12) {
            summaryCard

            Text("Review your answers (\(total))")
                .font(Theme.font(16, .heavy))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Array(pageStart..<pageEnd), id: \.self) { i in
                resultCard(i)
                    .opacity(celebrate ? 1 : 0)
                    .offset(y: celebrate ? 0 : 18)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.85)
                            .delay(0.1 + Double(i - pageStart) * 0.06),
                        value: celebrate)
            }

            if pageCount > 1 { pager }

            Button("Done") {
                reportComplete()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .onAppear { celebrate = true }
    }

    private var summaryCard: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.green).frame(width: 64, height: 64)
                    .overlay(
                        Circle().stroke(Theme.green.opacity(0.18), lineWidth: 8)
                            .scaleEffect(1.25))
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(celebrate ? 1 : 0.2)
            .opacity(celebrate ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.55), value: celebrate)
            Text("Results").font(Theme.font(20, .bold)).foregroundStyle(Theme.text)
            Text("First-answer correct: \(firstCorrectCount)/\(total)")
                .font(Theme.font(15, .semibold))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var pager: some View {
        HStack {
            Button {
                if reviewPage > 0 { reviewPage -= 1 }
            } label: {
                Text("← Back")
                    .font(Theme.font(15, .bold))
                    .foregroundStyle(reviewPage == 0 ? Theme.muted : Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(reviewPage == 0)
            Spacer()
            Text("Page \(reviewPage + 1) of \(pageCount)")
                .font(Theme.font(13, .bold))
                .foregroundStyle(Theme.muted)
            Spacer()
            Button {
                if reviewPage < pageCount - 1 { reviewPage += 1 }
            } label: {
                Text("Next →")
                    .font(Theme.font(15, .bold))
                    .foregroundStyle(reviewPage >= pageCount - 1 ? Theme.muted : Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(reviewPage >= pageCount - 1)
        }
        .padding(.horizontal, 4)
    }

    private func resultCard(_ i: Int) -> some View {
        let q = items[i]
        let firstOK = firstChoices[i] == q.correct
        let secondOK = secondChoices[i] == q.correct
        let correctLetter = q.choices.indices.contains(q.correct) ? q.choices[q.correct].letter : "?"
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Question \(i + 1) of \(total)")
                    .font(Theme.font(12, .heavy))
                    .foregroundStyle(Theme.muted)
                    .textCase(.uppercase)
                Spacer()
                Text(firstOK ? "Correct" : "Missed")
                    .font(Theme.font(13, .heavy))
                    .foregroundStyle(firstOK ? Theme.green : Theme.red)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(
                        Capsule().fill((firstOK ? Theme.green : Theme.red).opacity(0.14)))
            }
            Text(q.stem)
                .font(Theme.font(18, .bold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if didSecondPass {
                    resultPill("second: \(secondOK ? "correct" : "missed")", ok: secondOK)
                }
                resultPill("Correct answer: \(correctLetter)", ok: nil)
            }
            if !q.explanation.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Why the answer is \(correctLetter)")
                        .font(Theme.font(13, .heavy))
                        .foregroundStyle(Theme.text)
                    Text(q.explanation)
                        .font(Theme.font(16))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
            }
            if aiActive && didSecondPass {
                aiFeedbackView(i)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// Personalized AI feedback on the student's second-pass argument, grounded
    /// in the official explanation. Shows a "reviewing…" placeholder while the
    /// grader runs, and nothing if AI was unreachable (fail-safe).
    @ViewBuilder
    private func aiFeedbackView(_ i: Int) -> some View {
        if let fb = aiFeedback[i] {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(labelText(fb.verdict))
                        .font(Theme.font(11, .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(verdictColor(fb.verdict)))
                    Text("Coach feedback on your reasoning")
                        .font(Theme.font(12, .bold))
                        .foregroundStyle(Theme.accent)
                }
                if !fb.feedback.isEmpty {
                    Text(fb.feedback)
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !fb.keyPoint.isEmpty {
                    (Text("Key point: ").font(Theme.font(13, .bold))
                        + Text(fb.keyPoint).font(Theme.font(13)))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Source: \(fb.source)")
                    .font(Theme.font(12)).italic()
                    .foregroundStyle(Theme.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.22), lineWidth: 1))
        } else if aiGrading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Your coach is reviewing your reasoning…")
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func labelText(_ verdict: String) -> String {
        verdict.replacingOccurrences(of: "_", with: " ")
    }

    private func verdictColor(_ verdict: String) -> Color {
        switch verdict {
        case "sound": return Theme.green
        case "partially_sound": return Theme.amber
        case "flawed": return Theme.red
        default: return Theme.muted
        }
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
        if timeLeft < 0 { slowCount += 1 }  // ran past the limit (pacing signal)
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
        // The diagnostic is single-pass; otherwise offer a second look on misses.
        if diagnosticKind != nil || wrongFirst.isEmpty {
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
        if aiActive && didSecondPass {
            gradeAllReasoning()
        }
    }

    /// Grade every second-pass argument against its official explanation (the
    /// named source), concurrently. Fail-safe: items with no feedback simply show
    /// none. Runs off the main actor; results are applied back on the main actor.
    private func gradeAllReasoning() {
        aiGrading = true
        let snapshot = items
        let firsts = firstChoices
        let seconds = secondChoices
        let reasons = reasoning
        Task {
            var out: [Int: AiFeedback] = [:]
            await withTaskGroup(of: (Int, AiFeedback?).self) { group in
                for i in snapshot.indices {
                    let arg = (reasons[i] ?? "").trimmingCharacters(in: .whitespaces)
                    guard arg.count >= 3 else { continue }
                    let q = snapshot[i]
                    let chosen = seconds[i] ?? firsts[i]
                    let studentLetter =
                        chosen.flatMap { q.choices.indices.contains($0) ? q.choices[$0].letter : nil }
                        ?? ""
                    let correctLetter =
                        q.choices.indices.contains(q.correct) ? q.choices[q.correct].letter : ""
                    group.addTask {
                        let fb = await AIClient.gradeReasoning(
                            question: q.stem, choices: q.choices,
                            studentChoice: studentLetter, correctChoice: correctLetter,
                            explanation: q.explanation, studentReasoning: arg)
                        return (i, fb)
                    }
                }
                for await (i, fb) in group {
                    if let fb { out[i] = fb }
                }
            }
            await MainActor.run {
                aiFeedback = out
                aiGrading = false
            }
        }
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
        progress.recordPacing(slow: slowCount, total: total)
        if let diagnosticKind {
            // Keep the most informative kind, and lock the daily diagnostic for
            // today (synced). Attempts above already refine scores additively.
            app.setDiagnosticKind(diagnosticKind)
            app.markDiagnosticDone()
        }
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
        let over = s < 0
        let v = abs(s)
        let m = v / 60
        let sec = v % 60
        return "\(over ? "+" : "")\(m):\(sec < 10 ? "0" : "")\(sec)"
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
