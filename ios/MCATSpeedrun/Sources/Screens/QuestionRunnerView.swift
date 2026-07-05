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
    private enum Verdict { case correct, shaky, missed }
    private struct ConceptCard { var title: String?; var svg: String? }

    @State private var stage: Stage = .first
    @State private var idx = 0
    @State private var selected: Int? = nil
    @State private var confidence: ConfidenceLevel? = nil
    // Answers are keyed by position in `items` (questions may repeat).
    @State private var firstChoices: [Int: Int] = [:]
    @State private var firstConfidence: [Int: ConfidenceLevel] = [:]
    @State private var secondChoices: [Int: Int] = [:]
    @State private var didSecondPass = false
    @State private var timeLeft: Int
    @State private var reported = false
    @State private var recorded = false
    // AI (second-pass reasoning grading), keyed by position in `items`.
    @State private var reasoning: [Int: String] = [:]
    @State private var aiFeedback: [Int: AiFeedback] = [:]
    @State private var aiGrading = false
    // Overtime pulse + pacing tally (questions past the limit).
    @State private var pulse = false
    @State private var slowCount = 0
    // Review flow: a grid overview, then a per-question walk-through with an AI
    // concept title + diagram (WKWebView) + minimal text.
    @State private var reviewMode = false
    @State private var reviewIdx = 0
    @State private var showQ = false
    // Every question must be looked at (right and wrong) before finishing.
    @State private var viewed: Set<Int> = []
    @State private var cards: [Int: ConceptCard] = [:]
    @State private var cardLoading: Set<Int> = []

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
                        actionRow
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
            MarkdownContent(text: q.stem, size: 18, weight: .semibold)
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
                Text(mcatMarkdownAttr(choice.text))
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

    private var actionRow: some View {
        HStack(spacing: 10) {
            if idx > 0 {
                Button("← Back") { goBack() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            submitButton
        }
    }

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

    // Go back to the previous question, keeping the current partial answer.
    private func goBack() {
        guard idx > 0 else { return }
        if stage == .first {
            firstChoices[idx] = selected
            firstConfidence[idx] = confidence
            idx -= 1
            selected = firstChoices[idx]
            confidence = firstConfidence[idx]
        } else {
            secondChoices[idx] = selected
            idx -= 1
            selected = secondChoices[idx]
        }
        resetTimer()
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

    // MARK: - Results (grid overview → per-question walk-through)

    private var resultsView: some View {
        Group {
            if reviewMode { reviewWalkthrough } else { reviewOverview }
        }
    }

    private func verdict(_ i: Int) -> Verdict {
        let firstOK = firstChoices[i] == items[i].correct
        if firstOK {
            if let v = aiFeedback[i]?.verdict, v == "flawed" || v == "partially_sound" {
                return .shaky
            }
            return .correct
        }
        if didSecondPass && secondChoices[i] == items[i].correct { return .shaky }
        return .missed
    }
    private func verdictColor(_ v: Verdict) -> Color {
        switch v {
        case .correct: return Theme.green
        case .shaky: return Theme.amber
        case .missed: return Theme.red
        }
    }
    private func verdictText(_ v: Verdict) -> String {
        switch v {
        case .correct: return "Correct"
        case .shaky: return "Shaky reasoning"
        case .missed: return "Missed"
        }
    }

    private var allViewed: Bool {
        !items.isEmpty && items.indices.allSatisfy { viewed.contains($0) }
    }
    private func firstUnviewed() -> Int {
        items.indices.first { !viewed.contains($0) } ?? 0
    }
    private func keyText(_ i: Int) -> String {
        if let fb = aiFeedback[i], !(fb.keyPoint.isEmpty && fb.feedback.isEmpty) {
            return fb.keyPoint.isEmpty ? fb.feedback : fb.keyPoint
        }
        return items[i].explanation
    }
    private func sourceText(_ i: Int) -> String {
        if let fb = aiFeedback[i] { return "Source: \(fb.source)" }
        return "Grounded in the official explanation"
    }

    // Overview: mascot summary + a tap-to-review grid + legend.
    private var reviewOverview: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                MascotView(size: 82, mood: firstCorrectCount * 2 >= total ? .happy : .neutral)
                Text("\(firstCorrectCount) of \(total) on first try")
                    .font(Theme.font(24, .heavy)).foregroundStyle(Theme.text)
                Text("Let's walk through them together — one at a time.")
                    .font(Theme.font(15)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("Tap a question to review")
                    .font(Theme.font(15, .heavy)).foregroundStyle(Theme.text)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                    spacing: 12
                ) {
                    ForEach(items.indices, id: \.self) { i in
                        Button { startReview(i) } label: { tile(i) }.buttonStyle(.plain)
                    }
                }
                legend
            }
            .cardStyle()

            if allViewed {
                Button("Go to dashboard") {
                    reportComplete()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button(viewed.isEmpty ? "Start review" : "Continue review") {
                    startReview(firstUnviewed())
                }
                .buttonStyle(PrimaryButtonStyle())
                Text("Review every question — right and wrong — to finish.")
                    .font(Theme.font(13, .semibold)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func tile(_ i: Int) -> some View {
        let c = verdictColor(verdict(i))
        let seen = viewed.contains(i)
        return VStack(spacing: 6) {
            Text("\(i + 1)").font(Theme.font(22, .heavy)).foregroundStyle(c)
            ZStack {
                RoundedRectangle(cornerRadius: 5).stroke(c, lineWidth: 2)
                    .frame(width: 17, height: 17).opacity(seen ? 1 : 0.5)
                if seen {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black)).foregroundStyle(c)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(RoundedRectangle(cornerRadius: 16).fill(c.opacity(0.15)))
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(Theme.green, "Correct")
            legendItem(Theme.amber, "Shaky reasoning")
            legendItem(Theme.red, "Missed")
            Spacer(minLength: 0)
        }
    }
    private func legendItem(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4).stroke(c, lineWidth: 2).frame(width: 12, height: 12)
            Text(label).font(Theme.font(13, .bold)).foregroundStyle(c)
        }
    }

    // Per-question walk-through: concept title + AI diagram + minimal text.
    // "Show question" opens a full-page takeover (question + options).
    @ViewBuilder
    private var reviewWalkthrough: some View {
        if showQ {
            questionTakeover(items[reviewIdx])
        } else {
            reviewCardView(reviewIdx, items[reviewIdx])
        }
    }

    private func questionTakeover(_ q: Question) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("QUESTION \(reviewIdx + 1) OF \(total)")
                .font(Theme.font(13, .heavy)).foregroundStyle(Theme.muted)
            MarkdownContent(text: q.stem, size: 20, weight: .bold)
            ForEach(Array(q.choices.enumerated()), id: \.element.id) { idx, choice in
                let isCorrect = idx == q.correct
                HStack(spacing: 14) {
                    Text(choice.letter).font(Theme.font(16, .bold))
                        .foregroundStyle(isCorrect ? .white : Theme.text)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(isCorrect ? Theme.green : Theme.surface2))
                    Text(mcatMarkdownAttr(choice.text)).font(Theme.font(18))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isCorrect ? Theme.green.opacity(0.12) : Theme.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isCorrect ? Theme.green : Theme.border, lineWidth: 1.5))
            }
            Button("← Back to feedback") { showQ = false }
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func reviewCardView(_ i: Int, _ q: Question) -> some View {
        let v = verdict(i)
        let correctLetter = q.choices.indices.contains(q.correct) ? q.choices[q.correct].letter : "?"
        let card = cards[i]
        return VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(items.indices, id: \.self) { j in
                    Capsule().fill(verdictColor(verdict(j)))
                        .frame(width: 26, height: j == reviewIdx ? 11 : 8)
                        .opacity(j == reviewIdx ? 1 : 0.55)
                        .onTapGesture { startReview(j) }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text(verdictText(v))
                        .font(Theme.font(13, .heavy)).foregroundStyle(verdictColor(v))
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(verdictColor(v).opacity(0.14)))
                    Text("\(reviewIdx + 1) / \(total)")
                        .font(Theme.font(13, .bold)).foregroundStyle(Theme.muted)
                    Spacer()
                    MascotView(size: 40, mood: v == .correct ? .happy : .neutral)
                }

                if let title = card?.title, !title.isEmpty {
                    Text(title).font(Theme.font(21, .heavy)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if aiActive {
                    if let svg = card?.svg, !svg.isEmpty {
                        SVGWebView(
                            svg: svg,
                            textColor: app.darkMode ? "#E6E8F0" : "#1F2340"
                        )
                        .frame(height: 210)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface2))
                    } else if cardLoading.contains(i) {
                        GeneratingDots()
                    }
                }

                resultPill("Answer \(correctLetter)", ok: nil)
                    .frame(maxWidth: .infinity)

                if !keyText(i).isEmpty {
                    Text(mcatMarkdownAttr(keyText(i)))
                        .font(Theme.font(18)).foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Show question") { showQ = true }
                    .font(Theme.font(13, .bold)).foregroundStyle(Theme.muted)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)

                Text(sourceText(i))
                    .font(Theme.font(11)).italic().foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

            HStack(spacing: 10) {
                Button("← Back") { reviewGo(-1) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(reviewIdx == 0).opacity(reviewIdx == 0 ? 0.5 : 1)
                if reviewIdx < total - 1 {
                    Button("Next →") { reviewGo(1) }.buttonStyle(PrimaryButtonStyle())
                } else if allViewed {
                    Button("Done") {
                        reportComplete()
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("Review remaining") { startReview(firstUnviewed()) }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }

            Button("← All questions") { reviewMode = false }
                .font(Theme.font(13, .bold)).foregroundStyle(Theme.muted).buttonStyle(.plain)
        }
    }

    private func startReview(_ i: Int) {
        reviewMode = true
        reviewIdx = i
        showQ = false
        viewed.insert(i)
        loadCard(i)
    }
    private func reviewGo(_ delta: Int) {
        let next = reviewIdx + delta
        guard next >= 0, next < total else { return }
        reviewIdx = next
        showQ = false
        viewed.insert(next)
        loadCard(next)
    }
    private func loadCard(_ i: Int) {
        guard aiActive, cards[i] == nil, !cardLoading.contains(i) else { return }
        cardLoading.insert(i)
        let q = items[i]
        Task {
            let card = await AIClient.conceptCard(question: q.stem, explanation: q.explanation)
            await MainActor.run {
                cards[i] = ConceptCard(title: card.title, svg: card.svg)
                cardLoading.remove(i)
            }
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
        firstConfidence[idx] = confidence
        if timeLeft < 0 { slowCount += 1 }  // ran past the limit (pacing signal)
        if idx + 1 < total {
            idx += 1
            selected = firstChoices[idx]  // restore if revisiting after a Back
            confidence = firstConfidence[idx]
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
        // Record the first-try score so the roadmap node shows a tally.
        let correct = items.indices.filter { firstChoices[$0] == items[$0].correct }.count
        app.completeActiveLaunch(score: BlockScore(correct: correct, total: items.count))
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
