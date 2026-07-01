// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// App-wide mutable state, injected as an @EnvironmentObject. Holds UI prefs
// (dark mode, sound), the dev flag, and roadmap progress. Today this is local;
// later it is backed by the Rust engine + sync so it survives and matches the
// desktop app.

import SwiftUI

final class AppState: ObservableObject {
    enum Keys {
        static let dark = "mcat.darkMode"
        static let sound = "mcat.sound"
    }

    @Published var darkMode: Bool {
        didSet { UserDefaults.standard.set(darkMode, forKey: Keys.dark) }
    }
    @Published var soundOn: Bool {
        didSet {
            UserDefaults.standard.set(soundOn, forKey: Keys.sound)
            SoundManager.shared.setEnabled(soundOn)
        }
    }

    @Published var profileName: String = ""
    @Published var profileEmail: String = ""
    var isDev: Bool { profileEmail.lowercased() == "dev@mcat.com" }
    /// Name to show in the UI, with a sensible fallback.
    var displayName: String {
        if !profileName.isEmpty { return profileName }
        if !profileEmail.isEmpty { return String(profileEmail.split(separator: "@").first ?? "") }
        return "Your account"
    }

    // Roadmap progress: stable block keys (slugs) that are complete. Keys match
    // the desktop planner exactly, so progress syncs across devices.
    @Published var completedKeys: Set<String> = []
    // Dev "Set mastery" override (0...100). When set, dashboard scores reflect it.
    @Published var devMastery: Double? { didSet { syncHook?() } }
    // Synced study settings + streak.
    @Published var examDate: Date? { didSet { syncHook?() } }
    @Published var dailyMinutes: Int = 120 { didSet { syncHook?() } }
    @Published var streak: Int = 0 { didSet { syncHook?() } }
    // Last day the streak was credited ("yyyy-MM-dd"); guards double-awards.
    @Published var lastStreakDate: String?
    // Diagnostic kind taken ("quick"/"standard"/"best_estimate"); enables the
    // low-confidence readiness estimate (mirrors desktop). Synced.
    @Published var diagnosticKind: String? { didSet { syncHook?() } }
    var diagnosticDone: Bool { diagnosticKind != nil }
    // Date ("yyyy-MM-dd") of the most recent diagnostic (initial or daily). The
    // daily diagnostic is available once this isn't today; synced across devices
    // so one diagnostic per day counts for both apps.
    @Published var lastDiagnosticDate: String? { didSet { syncHook?() } }
    var dailyDiagnosticAvailable: Bool {
        lastDiagnosticDate != AppState.dayString(Date())
    }
    // AI features on/off (on by default); off = the no-AI experience. Synced.
    @Published var aiEnabled: Bool = true { didSet { syncHook?() } }
    // The roadmap block currently being worked on (so finishing it marks it done).
    private var activeLaunchKey: String?

    /// Set by the sync layer; called whenever a synced field changes so the
    /// change is pushed to the cloud (the sync layer guards against loops).
    var syncHook: (() -> Void)?

    init() {
        darkMode = UserDefaults.standard.bool(forKey: Keys.dark)
        soundOn = (UserDefaults.standard.object(forKey: Keys.sound) as? Bool) ?? true
        SoundManager.shared.setEnabled(soundOn)
    }

    /// Days until the exam (used by the dashboard ring); nil if no date set.
    var daysToGo: Int? {
        guard let examDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: examDate).day ?? 0
        return max(0, days)
    }

    // MARK: Roadmap

    /// Study phase from the exam countdown (mirrors the desktop planner).
    var phase: String {
        guard let d = daysToGo else { return "foundation" }
        if d <= 14 { return "final" }
        if d <= 45 { return "sharpen" }
        return "foundation"
    }
    var phaseLabel: String {
        switch phase {
        case "final": return "Final stretch — full run-throughs"
        case "sharpen": return "Sharpening — mixed practice + full-lengths"
        default: return "Foundation — build coverage"
        }
    }

    /// Today's roadmap, composed for the current phase + daily study time.
    var roadmap: [RoadmapItem] { MockData.roadmap(phase: phase, dailyMinutes: dailyMinutes) }

    var total: Int { roadmap.count }
    var doneCount: Int {
        roadmap.reduce(0) { $0 + (completedKeys.contains($1.key) ? 1 : 0) }
    }
    var firstIncomplete: Int {
        roadmap.firstIndex { !completedKeys.contains($0.key) } ?? total
    }
    var allDone: Bool { total > 0 && doneCount >= total }

    func status(_ i: Int) -> BlockStatus {
        let items = roadmap
        guard items.indices.contains(i) else { return .locked }
        if completedKeys.contains(items[i].key) { return .done }
        if i == firstIncomplete { return .active }
        return .locked
    }

    /// Record which roadmap block the user is about to do, so completing the
    /// study screen marks it done (mirrors "doing the task completes the block").
    func beginLaunch(_ i: Int) {
        let items = roadmap
        activeLaunchKey = items.indices.contains(i) ? items[i].key : nil
    }

    func markDone(_ i: Int) {
        let items = roadmap
        guard items.indices.contains(i) else { return }
        markDone(key: items[i].key)
    }

    private func markDone(key: String) {
        let wasAllDone = allDone
        completedKeys.insert(key)
        if !wasAllDone && allDone {
            awardStreak()
            SoundManager.shared.streak()
        }
        syncHook?()
    }

    /// Credit today's streak at most once per day (mirrors the desktop rule:
    /// +1 if yesterday was credited, otherwise reset to 1).
    private func awardStreak() {
        let today = AppState.dayString(Date())
        if lastStreakDate == today { return }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())
            .map(AppState.dayString)
        streak = (lastStreakDate == yesterday) ? streak + 1 : 1
        lastStreakDate = today
    }

    /// Union in roadmap completion from a remote sync (never overwrites local
    /// progress) without re-triggering a push.
    func applyRemoteCompleted(_ set: Set<String>) {
        completedKeys.formUnion(set)
    }

    /// Called by a study screen that was launched from the roadmap when it finishes.
    func completeActiveLaunch() {
        if let key = activeLaunchKey {
            markDone(key: key)
            activeLaunchKey = nil
        }
    }

    func resetRoadmap() {
        completedKeys.removeAll()
        activeLaunchKey = nil
        syncHook?()
    }

    // MARK: Diagnostic

    /// Record that today's diagnostic (initial or daily) is complete; synced.
    func markDiagnosticDone() {
        lastDiagnosticDate = AppState.dayString(Date())
    }

    /// Keep the most informative diagnostic kind (best_estimate > standard >
    /// quick) so a short daily run can't hide the readiness estimate a longer
    /// diagnostic already unlocked.
    func setDiagnosticKind(_ kind: String) {
        let rank = ["quick": 1, "standard": 2, "best_estimate": 3]
        if rank[kind, default: 0] >= rank[diagnosticKind ?? "", default: 0] {
            diagnosticKind = kind
        }
    }

    // MARK: Dates

    /// Shared date-only formatter ("yyyy-MM-dd") used for examDate, roadmapDate
    /// and streakDate so values round-trip with the desktop app.
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }
    static func dayDate(_ string: String) -> Date? { dayFormatter.date(from: string) }
}
