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

    // Bind settings to shared state so changing the exam date shifts the roadmap
    // phase (and syncs). Defaults to ~119 days out when no date is set yet.
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
            VStack(spacing: 16) {
                header
                identityCard
                streakCard
                studySettingsCard
                aiCard
                scoresSection
                footer
            }
            .padding(16)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ScreenHeader("Account", "Your profile, streak and scores.")
            Button {
                auth.signOut()
            } label: {
                Text("Log out").padding(.horizontal, 18)
            }
            .buttonStyle(SecondaryButtonStyle())
            .fixedSize()
        }
    }

    // MARK: - AI features toggle

    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $app.aiEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI features")
                        .font(Theme.font(16, .bold))
                        .foregroundStyle(Theme.text)
                    Text(
                        "Personalized feedback, CARS debate, and a study coach. "
                            + "Off = classic mode; everything still works and scores.")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)
        }
        .cardStyle()
    }

    // MARK: - Identity

    private var identityCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(
                    LinearGradient(
                        colors: [Theme.accent, Theme.accent2],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                Text(String(app.displayName.prefix(1)).uppercased())
                    .font(Theme.font(24, .heavy)).foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)

            VStack(spacing: 6) {
                Text(app.displayName).font(Theme.font(20, .bold)).foregroundStyle(Theme.text)
                Text(app.profileEmail).font(Theme.font(14, .semibold)).foregroundStyle(Theme.muted)
                if app.isDev {
                    Pill(text: "DEV MODE", color: Theme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - Streak

    private var streakCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.amber.opacity(0.14))
                Image(systemName: "flame.fill")
                    .font(Theme.font(22, .bold))
                    .foregroundStyle(Theme.amber)
            }
            .frame(width: 46, height: 46)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(app.streak)")
                    .font(Theme.font(34, .heavy))
                    .foregroundStyle(Theme.text)
                Text("day streak")
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(Theme.muted)
            }

            Spacer(minLength: 0)
        }
        .cardStyle()
    }

    // MARK: - Study settings

    private var studySettingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Study settings").font(Theme.font(16, .bold)).foregroundStyle(Theme.text)

            settingRow("Name") {
                TextField("Your name", text: $app.profileName)
                    .textInputAutocapitalization(.words)
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10).fill(Theme.surface2)
                    )
            }

            Rectangle().fill(Theme.border).frame(height: 1)

            settingRow("MCAT exam date") {
                DatePicker("", selection: examDate, displayedComponents: .date)
                    .labelsHidden()
                    .tint(Theme.accent)
            }

            Rectangle().fill(Theme.border).frame(height: 1)

            settingRow("Daily study time") {
                Picker("", selection: studyMinutes) {
                    ForEach(studyOptions, id: \.self) { minutes in
                        Text(minutesLabel(minutes)).tag(minutes)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Theme.accent)
            }

            Text("2 hrs/day recommended — blocks resize to fit.")
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.muted)

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

    // MARK: - Scores

    private var scoresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your scores")
                .font(Theme.font(18, .bold))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)

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

    // MARK: - Footer

    private var footer: some View {
        Text("Engine \(Engine.version())")
            .font(Theme.font(12, .semibold))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.muted)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func block(for kind: ScoreKind) -> ScoreBlock {
        let model = Scoring.model(app: app, progress: progress)
        switch kind {
        case .memory: return model.memory
        case .performance: return model.performance
        case .readiness: return model.readiness
        }
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
