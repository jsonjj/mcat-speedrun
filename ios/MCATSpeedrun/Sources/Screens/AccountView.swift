// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

struct AccountView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var sync: SyncManager
    @EnvironmentObject var progress: ProgressStore

    @State private var saved = false

    private let studyOptions = [30, 45, 60, 90, 120, 150, 180]
    private let recommended = 120.0

    private var model: DashboardModel { Scoring.model(app: app, progress: progress) }

    private var examDate: Binding<Date> {
        Binding(
            get: {
                app.examDate
                    ?? Calendar.current.date(byAdding: .day, value: 119, to: .now)
                    ?? .now
            },
            set: { app.examDate = $0 }
        )
    }
    private var studyMinutes: Binding<Int> {
        Binding(get: { app.dailyMinutes }, set: { app.dailyMinutes = $0 })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header.slideEnter(delay: 0.03, x: -36)
                profileCard.slideEnter(delay: 0.09, x: 36)

                sectionLabel("Study settings").slideEnter(delay: 0.15, x: -36)
                studySettingsCard.slideEnter(delay: 0.18, x: 36)

                sectionLabel("AI features").slideEnter(delay: 0.24, x: -36)
                aiCard.slideEnter(delay: 0.27, x: 36)

                sectionLabel("Your scores").slideEnter(delay: 0.33, x: -36)
                scoresList.slideEnter(delay: 0.36, x: 36)
                estimateCard.slideEnter(delay: 0.42, x: -36)

                footer.screenEnter(delay: 0.48)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ScreenHeader("Account", "Your profile, commitment, and progress.")
            Button { auth.signOut() } label: {
                Text("Log out").padding(.horizontal, 16)
            }
            .buttonStyle(SecondaryButtonStyle())
            .fixedSize()
        }
    }

    // MARK: - Profile (avatar · streak · days-to-exam · week dots)

    private var profileCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(
                        LinearGradient(
                            colors: [Theme.accent, Theme.accent2],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(String(app.displayName.prefix(1)).uppercased())
                        .font(Theme.font(24, .heavy)).foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.displayName)
                        .font(Theme.font(20, .bold)).foregroundStyle(Theme.text)
                    Text(app.profileEmail)
                        .font(Theme.font(13, .semibold)).foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)

                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text("🔥").font(.system(size: 15))
                        Text("\(app.streak)")
                            .font(Theme.font(22, .heavy)).foregroundStyle(Theme.amber)
                    }
                    Text("streak").font(Theme.font(11, .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }

            Divider().overlay(Theme.border).padding(.vertical, 14)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(app.daysToGo ?? 0)")
                        .font(Theme.font(26, .heavy)).foregroundStyle(Theme.accent)
                    Text("days to exam").font(Theme.font(12, .semibold))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 5) {
                        ForEach(0..<7, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(weekDots[i] ? Theme.green : Theme.surface2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(
                                            weekDots[i] ? Theme.green : Theme.border,
                                            lineWidth: 1))
                                .frame(width: 15, height: 15)
                        }
                    }
                    Text("this week").font(Theme.font(11, .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Study settings (+ pace bar)

    private var studySettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingRow("Name") {
                TextField("Your name", text: $app.profileName)
                    .textInputAutocapitalization(.words)
                    .font(Theme.font(15, .semibold)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
            }
            Divider().overlay(Theme.border)
            settingRow("MCAT exam date") {
                DatePicker("", selection: examDate, displayedComponents: .date)
                    .labelsHidden().tint(Theme.accent)
            }
            Divider().overlay(Theme.border)
            settingRow("Daily study time") {
                Picker("", selection: studyMinutes) {
                    ForEach(studyOptions, id: \.self) { m in
                        Text(minutesLabel(m)).tag(m)
                    }
                }
                .labelsHidden().pickerStyle(.menu).tint(Theme.accent)
            }

            paceBar

            Button(saved ? "Saved ✓" : "Save changes") {
                app.profileName = app.profileName.trimmingCharacters(in: .whitespaces)
                sync.pushLocal()
                withAnimation { saved = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation { saved = false }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .cardStyle()
    }

    private var paceBar: some View {
        let fill = min(1.0, Double(app.dailyMinutes) / recommended)
        let remaining = max(0.0, (recommended - Double(app.dailyMinutes)) / 60.0)
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Your pace").font(Theme.font(14, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Text("\(hrText(app.dailyMinutes)) of 2 hr")
                    .font(Theme.font(13, .semibold)).foregroundStyle(Theme.muted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track).frame(height: 10)
                    Capsule().fill(Theme.amber)
                        .frame(width: max(6, geo.size.width * fill), height: 10)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .overlay(alignment: .trailing) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.green)
                        .frame(width: 3, height: 16)
                }
            }
            .frame(height: 16)
            if remaining > 0 {
                Text("\(String(format: "%.1f", remaining)) hr more to hit the goal")
                    .font(Theme.font(12.5, .bold)).foregroundStyle(Theme.amber)
            } else {
                Text("✓ You're at the recommended pace")
                    .font(Theme.font(12.5, .bold)).foregroundStyle(Theme.green)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
    }

    // MARK: - AI features

    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $app.aiEnabled) {
                Text("Personalized AI")
                    .font(Theme.font(16, .bold)).foregroundStyle(Theme.text)
            }
            .tint(Theme.accent)
            Text("Off = classic mode. Everything still works and still scores.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                featureRow("Reasoning feedback", Theme.accent)
                featureRow("CARS debate", Theme.red)
                featureRow("Study coach", Theme.green)
            }
            .opacity(app.aiEnabled ? 1 : 0.45)
        }
        .cardStyle()
    }

    private func featureRow(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(label).font(Theme.font(14, .semibold)).foregroundStyle(Theme.text)
        }
    }

    // MARK: - Scores

    private var scoresList: some View {
        VStack(spacing: 12) {
            ForEach(ScoreKind.allCases) { kind in
                NavigationLink {
                    ScoreDetailView(kind: kind)
                } label: {
                    EvidenceCardView(
                        title: kind.title,
                        icon: kind.icon,
                        block: block(for: kind),
                        scaleMin: kind == .readiness ? 472 : 0,
                        scaleMax: kind == .readiness ? 528 : 100
                    )
                }
                .buttonStyle(.plain)
                .tapSound()
            }
        }
    }

    // Total = sum of the four section ranges once all four are estimated (matches
    // the Dashboard + Breakdown), independent of the overall readiness gate.
    private var estimateCard: some View {
        let ready = model.sections.filter { !$0.abstained }
        let allReady = model.sections.count == 4 && ready.count == 4
        let low = ready.reduce(0) { $0 + Int($1.low.rounded()) }
        let high = ready.reduce(0) { $0 + Int($1.high.rounded()) }
        let mid = (low + high) / 2
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Score estimate")
                    .font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Text(allReady ? "\(low)–\(high)" : "—")
                    .font(Theme.font(24, .heavy))
                    .foregroundStyle(allReady ? Theme.accent : Theme.muted)
            }
            VStack(spacing: 6) {
                RangeBarView(
                    lo: 472, hi: 528,
                    low: allReady ? Double(low) : 472,
                    high: allReady ? Double(high) : 472,
                    point: allReady ? Double(mid) : 472,
                    color: allReady ? Theme.accent : Theme.muted)
                HStack {
                    Text("472")
                    Spacer()
                    Text("500")
                    Spacer()
                    Text("528")
                }
                .font(Theme.font(11, .semibold)).foregroundStyle(Theme.muted)
            }
        }
        .cardStyle(tint: Theme.accent)
    }

    // MARK: - Footer

    private var footer: some View {
        Text("Engine \(Engine.version())")
            .font(Theme.font(12, .semibold)).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity).padding(.top, 4)
    }

    // MARK: - Helpers

    private var weekDots: [Bool] {
        var dots = Array(repeating: false, count: 7)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayIso = AppState.dayString(today)
        let todayIdx = (cal.component(.weekday, from: today) + 5) % 7  // Mon=0…Sun=6
        let span = app.lastStreakDate == todayIso ? min(app.streak, todayIdx + 1) : 0
        for k in 0..<span where todayIdx - k >= 0 { dots[todayIdx - k] = true }
        return dots
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.font(12, .heavy)).tracking(0.6)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func settingRow<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.font(13, .semibold)).foregroundStyle(Theme.muted)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func block(for kind: ScoreKind) -> ScoreBlock {
        switch kind {
        case .memory: return model.memory
        case .performance: return model.performance
        case .readiness: return model.readiness
        }
    }

    private func hrText(_ minutes: Int) -> String {
        minutes % 60 == 0
            ? "\(minutes / 60) hr"
            : String(format: "%.1f hr", Double(minutes) / 60)
    }

    private func minutesLabel(_ minutes: Int) -> String {
        let base: String
        if minutes < 60 {
            base = "\(minutes) min"
        } else if minutes % 60 == 0 {
            base = "\(minutes / 60) hr"
        } else {
            base = "\(minutes / 60) hr \(minutes % 60) min"
        }
        return minutes == 120 ? "\(base) (recommended)" : base
    }
}
