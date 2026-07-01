// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Engine-backed study store. The source of truth is the shared Rust engine's
// event log (memory reviews + performance attempts), held here as a JSON string
// and persisted to disk. Recording appends events via the engine's replay-union
// merge; scoring and scheduling are computed by the engine (see Engine.swift).
// The full engine log is synced across devices and folded in via the merge.

import Foundation

final class ProgressStore: ObservableObject {
    /// The engine state (event logs) as JSON — the source of truth.
    @Published private(set) var stateJSON: String = ProgressStore.emptyState
    /// The other device's full engine log (synced in), folded into scores.
    @Published private(set) var remoteLog: String = "{}"

    /// Set by the sync layer; called when local study changes so it's pushed.
    var syncHook: (() -> Void)?

    init() { load() }

    // MARK: - Recording (append to the log via the engine)

    func recordReview(section: SectionCode, cardKey: String, rating: Int) {
        let review = OutReview(
            id: UUID().uuidString, card_key: cardKey, section: section.rawValue,
            ts: Self.nowTs(), rating: rating)
        append(OutEvents(reviews: [review], attempts: []))
    }

    func recordBatch(_ items: [(section: SectionCode, questionKey: String, correct: Bool)]) {
        guard !items.isEmpty else { return }
        let batchId = UUID().uuidString
        let ts = Self.nowTs()
        let attempts = items.map {
            OutAttempt(
                id: UUID().uuidString, section: $0.section.rawValue,
                question_key: $0.questionKey, ts: ts, first_correct: $0.correct,
                batch_id: batchId)
        }
        append(OutEvents(reviews: [], attempts: attempts))
    }

    func reset() {
        stateJSON = Self.emptyState
        save()
        syncHook?()
    }

    private func append(_ events: OutEvents) {
        guard let data = try? JSONEncoder().encode(events),
            let json = String(data: data, encoding: .utf8)
        else { return }
        stateJSON = Engine.merge(state: stateJSON, other: json)
        save()
        syncHook?()
    }

    // MARK: - Cross-device sync (full engine log)

    /// Apply the other device's full engine log (JSON), synced in.
    func applyRemoteLog(_ json: String) {
        remoteLog = json.isEmpty ? "{}" : json
    }

    /// Our log replay-union merged with the remote log, for scoring.
    func combinedLogJSON() -> String {
        Engine.merge(state: stateJSON, other: remoteLog)
    }

    // MARK: - Event / log JSON shapes (match the Rust engine)

    private struct OutReview: Codable {
        var id: String
        var card_key: String
        var section: String
        var ts: Int64
        var rating: Int
    }
    private struct OutAttempt: Codable {
        var id: String
        var section: String
        var question_key: String
        var ts: Int64
        var first_correct: Bool
        var batch_id: String
    }
    private struct OutEvents: Codable {
        var reviews: [OutReview]
        var attempts: [OutAttempt]
    }

    // MARK: - Persistence

    private static let emptyState = "{\"reviews\":[],\"attempts\":[]}"
    private static func nowTs() -> Int64 { Int64(Date().timeIntervalSince1970) }

    private var fileURL: URL? {
        let fm = FileManager.default
        guard
            let dir = try? fm.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
        else { return nil }
        return dir.appendingPathComponent("mcat_engine_state.json")
    }

    private func save() {
        guard let url = fileURL else { return }
        try? stateJSON.data(using: .utf8)?.write(to: url)
    }

    private func load() {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
            let json = String(data: data, encoding: .utf8), !json.isEmpty
        else { return }
        stateJSON = json
    }
}
