// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// "Today's Path" — the daily roadmap, drawn as a vertical timeline tuned for
// phones. Each step is a node whose status (done / active / locked) comes from
// AppState; a connector line lights up as steps are completed and runs down to
// a streak goal at the bottom. Non-locked steps are large tappable rows that
// push their study destination onto the tab's stack and record the block, so
// finishing the study screen marks it done.

import SwiftUI

struct RoadmapView: View {
    @EnvironmentObject var app: AppState
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                phaseBadge
                legend
                banner
                timeline
            }
            .padding(16)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { appeared = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ScreenHeader("Today's Path", "\(app.doneCount) of \(app.total) done")
            if app.isDev {
                Button {
                    app.resetRoadmap()
                } label: {
                    Text("Reset roadmap").padding(.horizontal, 12)
                }
                .buttonStyle(SecondaryButtonStyle())
                .fixedSize()
            }
        }
    }

    // MARK: - Phase badge (adapts to exam date)

    private var phaseBadge: some View {
        let color: Color =
            app.phase == "final"
            ? Theme.red : (app.phase == "sharpen" ? Theme.amber : Theme.accent)
        let suffix = app.daysToGo.map { " · \($0) days to exam" } ?? ""
        return Text(app.phaseLabel + suffix)
            .font(Theme.font(13, .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().stroke(color.opacity(0.26), lineWidth: 1))
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(Theme.cyan, "Spaced Review")
            legendItem(Theme.amber, "Performance Set")
            legendItem(Theme.accent, "Section Practice")
            Spacer(minLength: 0)
        }
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(Theme.font(12, .semibold))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Unlock banner

    private var banner: some View {
        let done = app.allDone
        return HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.seal.fill" : "lock.fill")
                .font(Theme.font(16, .bold))
                .foregroundStyle(done ? Theme.green : Theme.accent)
            Text(done
                 ? "✓ Extra Practice unlocked"
                 : "Finish today's path to unlock Extra Practice")
                .font(Theme.font(15, .semibold))
                .foregroundStyle(done ? Theme.green : Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .cardStyle(tint: done ? Theme.green : nil)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(done ? Theme.green : Theme.accent)
                .frame(width: 4)
                .padding(.vertical, 12)
                .padding(.leading, 6)
        }
    }

    // MARK: - Vertical timeline

    private var timeline: some View {
        VStack(spacing: 0) {
            ForEach(Array(app.roadmap.enumerated()), id: \.element.id) { index, item in
                row(index: index, item: item)
            }
            streakRow
        }
    }

    private func row(index: Int, item: RoadmapItem) -> some View {
        let st = app.status(index)
        return VStack(alignment: .leading, spacing: 0) {
            if st == .locked {
                // Locked: a dimmed, non-interactive card (no NavigationLink).
                rowCard(index: index, item: item, status: st)
                    .opacity(0.55)
            } else {
                // Done / active: a tappable row that opens its study screen and
                // records the block so completing that screen marks it done.
                NavigationLink {
                    destinationView(for: item)
                } label: {
                    rowCard(index: index, item: item, status: st)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { app.beginLaunch(index) })
                .tapSound()
            }
            if app.isDev && st == .active {
                markDoneRow(index: index)
            }
        }
        // Cascade rows in as the path assembles.
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(
            .spring(response: 0.55, dampingFraction: 0.85).delay(Double(index) * 0.05),
            value: appeared)
    }

    private func rowCard(index: Int, item: RoadmapItem, status: BlockStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if status == .active {
                Pill(text: "UP NEXT", color: Theme.accent)
            }
            Text(item.label)
                .font(Theme.font(17, .bold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.sub)
                .font(Theme.font(13))
                .foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                Pill(text: "\(item.minutes) Min")
                Spacer(minLength: 0)
                if status != .locked {
                    Image(systemName: "chevron.right")
                        .font(Theme.font(13, .bold))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .cardStyle(tint: cardTint(status, item.activity))
        // Reserve the leading gutter for the node + connector, and add spacing
        // below so the connector line runs continuously to the next node.
        .padding(.leading, 70)
        .padding(.bottom, 16)
        .overlay(alignment: .topLeading) {
            gutter(index: index, item: item, status: status)
        }
    }

    /// Dev-only control shown beneath the active node to force it complete.
    /// Rendered as a sibling (not inside the NavigationLink) so its tap can't
    /// trigger navigation; a track-coloured stub keeps the connector unbroken.
    private func markDoneRow(index: Int) -> some View {
        HStack(spacing: 0) {
            Button {
                app.markDone(index)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Mark done")
                }
                .font(Theme.font(13, .bold))
                .foregroundStyle(Theme.green)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.green.opacity(0.14)))
                .overlay(Capsule().stroke(Theme.green.opacity(0.30), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.leading, 70)
        .padding(.bottom, 16)
        .overlay(alignment: .topLeading) { connectorStub }
    }

    /// A 2pt track-coloured line centred in the 56pt leading gutter, spanning
    /// the host view's full height so the timeline reads as continuous.
    private var connectorStub: some View {
        Rectangle()
            .fill(Theme.track)
            .frame(width: 2)
            .frame(maxHeight: .infinity)
            .frame(width: 56)
            .allowsHitTesting(false)
    }

    /// The leading column: a two-tone connector line with the node on top.
    /// The segment above the node uses the previous step's completion; the
    /// segment below uses this step's — so the line between two nodes is a
    /// single colour (accent when the node above is done, else track).
    private func gutter(index: Int, item: RoadmapItem, status: BlockStatus) -> some View {
        let topColor: Color = index > 0
            ? (app.status(index - 1) == .done ? Theme.accent : Theme.track)
            : .clear
        let bottomColor: Color = status == .done ? Theme.accent : Theme.track
        return ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle().fill(topColor).frame(width: 2, height: 28)
                Rectangle().fill(bottomColor).frame(width: 2).frame(maxHeight: .infinity)
            }
            NodeCircle(status: status, activity: item.activity)
        }
        .frame(width: 56)
    }

    private var streakRow: some View {
        let lastIndex = app.roadmap.count - 1
        let lastDone = lastIndex >= 0 && app.status(lastIndex) == .done
        let done = app.allDone
        return VStack(alignment: .leading, spacing: 4) {
            Text(done ? "Streak earned!" : "Finish for your streak")
                .font(Theme.font(16, .bold))
                .foregroundStyle(done ? Theme.green : Theme.text)
            Text(done
                 ? "Great work today — see you tomorrow."
                 : "Complete every step to keep your streak alive.")
                .font(Theme.font(13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle(tint: done ? Theme.green : Theme.amber)
        .padding(.leading, 70)
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(lastDone ? Theme.accent : Theme.track)
                    .frame(width: 2, height: 28)
                flameNode
            }
            .frame(width: 56)
        }
    }

    private var flameNode: some View {
        ZStack {
            if app.allDone {
                Circle().fill(Theme.green)
                Image(systemName: "flame.fill")
                    .font(Theme.font(24, .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().fill(Theme.amber.opacity(0.15))
                Circle().strokeBorder(Theme.amber.opacity(0.45),
                                      style: StrokeStyle(lineWidth: 2, dash: [4]))
                Image(systemName: "flag.checkered")
                    .font(Theme.font(22, .bold))
                    .foregroundStyle(Theme.amber)
            }
        }
        .frame(width: 56, height: 56)
    }

    // MARK: - Helpers

    private func cardTint(_ status: BlockStatus, _ activity: Activity) -> Color? {
        switch status {
        case .active: return activity.color
        case .done: return Theme.green
        case .locked: return nil
        }
    }

    @ViewBuilder
    private func destinationView(for item: RoadmapItem) -> some View {
        switch item.destination {
        case .flashcards(let sections):
            FlashcardsView(sections: sections)
        case .questions(let cfg):
            QuestionRunnerView(config: cfg)
        case .cars:
            // AI on → interactive Author Duel; AI off → CARS MCQ practice.
            if app.aiEnabled {
                CarsView()
            } else {
                QuestionRunnerView(
                    config: QuizConfig(
                        title: "CARS Practice", sections: [.cars], count: 10, seconds: 120))
            }
        }
    }
}

// MARK: - Timeline node

private struct NodeCircle: View {
    let status: BlockStatus
    let activity: Activity
    @State private var pulse = false

    var body: some View {
        ZStack {
            // "Radar ping" behind the active node.
            if status == .active {
                Circle()
                    .stroke(activity.color.opacity(0.45), lineWidth: 3)
                    .scaleEffect(pulse ? 1.3 : 1.0)
                    .opacity(pulse ? 0 : 0.9)
            }
            switch status {
            case .done:
                Circle().fill(Theme.green)
                Image(systemName: "checkmark")
                    .font(Theme.font(22, .bold))
                    .foregroundStyle(.white)
            case .active:
                Circle().fill(activity.color).padding(5)
                Circle().strokeBorder(activity.color,
                                      style: StrokeStyle(lineWidth: 2, dash: [4]))
                Image(systemName: activity.icon)
                    .font(Theme.font(20, .bold))
                    .foregroundStyle(.white)
            case .locked:
                Circle().fill(Theme.surface2)
                Circle().strokeBorder(Theme.border, lineWidth: 1.5)
                Image(systemName: "lock.fill")
                    .font(Theme.font(17, .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 56, height: 56)
        .onAppear {
            guard status == .active else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

#Preview {
    NavigationStack { RoadmapView() }
        .environmentObject(AppState())
}
