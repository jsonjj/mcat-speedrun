// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Bridges the signed-in user's Firestore document <-> AppState. A snapshot
// listener applies remote changes locally (real-time autosync), and a hook on
// AppState pushes local changes up. Both apps (iOS + desktop) read/write the
// same users/{uid} document, so progress stays in sync across devices.

import Combine
import FirebaseFirestore
import Foundation

@MainActor
final class SyncManager: ObservableObject {
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private weak var app: AppState?
    private weak var progress: ProgressStore?
    private var uid: String?
    private var applyingRemote = false

    func attach(app: AppState, progress: ProgressStore) {
        self.app = app
        self.progress = progress
        app.syncHook = { [weak self] in self?.pushLocal() }
        progress.syncHook = { [weak self] in self?.pushLocal() }
    }

    func start(uid: String, name: String?, email: String?) {
        guard let app else { return }
        self.uid = uid
        listener?.remove()

        if let email, !email.isEmpty { app.profileEmail = email }
        if let name, !name.isEmpty { app.profileName = name }

        let ref = db.collection("users").document(uid)
        listener = ref.addSnapshotListener { [weak self] snap, _ in
            guard let self, let app = self.app else { return }
            guard let data = snap?.data(), !data.isEmpty else {
                // First login on this account — seed the doc from local state.
                self.pushLocal()
                return
            }
            self.applyingRemote = true
            if let n = data["name"] as? String, !n.isEmpty { app.profileName = n }
            if let dm = data["devMastery"] as? Double { app.devMastery = dm }
            if data["devMastery"] == nil { app.devMastery = nil }
            if let ed = data["examDate"] as? String, !ed.isEmpty {
                app.examDate = AppState.dayDate(String(ed.prefix(10)))
            }
            if let dmn = data["dailyMinutes"] as? Int { app.dailyMinutes = dmn }
            if let st = data["streak"] as? Int { app.streak = st }
            if let sd = data["streakDate"] as? String {
                app.lastStreakDate = sd.isEmpty ? nil : sd
            }
            if let dk = data["diagnosticKind"] as? String {
                app.diagnosticKind = dk.isEmpty ? nil : dk
            }
            if let ai = data["aiEnabled"] as? Bool {
                app.aiEnabled = ai
            }
            // The desktop's full engine log, so scores combine across devices.
            if let ldesk = data["mcatLogDesktop"] as? String {
                self.progress?.applyRemoteLog(ldesk)
            }
            // Roadmap progress: union in the desktop's completed blocks, but only
            // when its plan is for today. We never clear local progress on a stale
            // remote date (that would wipe today's work); the roadmap resets per
            // day via a fresh plan, and completion is unioned (never overwritten).
            if (data["roadmapDate"] as? String) == AppState.dayString(Date()),
                let json = data["completedBlocksDesktop"] as? String,
                let raw = json.data(using: .utf8),
                let keys = try? JSONDecoder().decode([String].self, from: raw)
            {
                app.applyRemoteCompleted(Set(keys))
            }
            self.applyingRemote = false
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
        uid = nil
    }

    func pushLocal() {
        guard !applyingRemote, let uid, let app else { return }
        // Only push keys that belong to today's roadmap, encoded as JSON so the
        // desktop (which speaks Firestore REST) reads the same string.
        let currentKeys = Set(app.roadmap.map { $0.key })
        let completed = app.completedKeys.filter { currentKeys.contains($0) }.sorted()
        let completedJSON =
            (try? JSONEncoder().encode(completed))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        var data: [String: Any] = [
            "name": app.profileName,
            "email": app.profileEmail,
            "dailyMinutes": app.dailyMinutes,
            "streak": app.streak,
            "streakDate": app.lastStreakDate ?? "",
            "completedBlocksIos": completedJSON,
            "roadmapDate": AppState.dayString(Date()),
            "diagnosticKind": app.diagnosticKind ?? "",
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let ed = app.examDate { data["examDate"] = AppState.dayString(ed) }
        data["aiEnabled"] = app.aiEnabled
        data["devMastery"] = app.devMastery ?? FieldValue.delete()
        if let progress {
            data["mcatLogIos"] = progress.stateJSON
        }
        db.collection("users").document(uid).setData(data, merge: true)
    }
}
