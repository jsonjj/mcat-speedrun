// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Loads the bundled MCAT content pack (the SAME content_pack_v1.json the desktop
// imports) plus the topic taxonomy, so the iOS app has the full question bank
// and flashcards offline. Coverage is derived statically from the content —
// identical to the desktop rule (a topic is "covered" when it has both a memory
// and a performance item; CARS needs only a performance item).

import CryptoKit
import Foundation

/// Stable, cross-platform content key. Both apps derive the same key from the
/// same content, so per-card state and events line up when synced.
func mcatContentKey(_ parts: [String]) -> String {
    let joined = parts.joined(separator: "|")
    let digest = SHA256.hash(data: Data(joined.utf8))
    return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
}

final class ContentStore {
    static let shared = ContentStore()

    let questions: [Question]
    let flashcards: [Flashcard]

    // Topic sets per section, used for coverage.
    private let memoryTopics: [SectionCode: Set<String>]
    private let perfTopics: [SectionCode: Set<String>]
    private let taxonomyTopics: [SectionCode: Set<String>]

    struct Coverage {
        var covered: Int
        var total: Int
        var pct: Double
    }

    private init() {
        let pack = ContentStore.decode(PackFile.self, resource: "content_pack_v1")
        let tax = ContentStore.decode(TaxFile.self, resource: "taxonomy")

        var qs: [Question] = []
        var cards: [Flashcard] = []
        var mem: [SectionCode: Set<String>] = [:]
        var perf: [SectionCode: Set<String>] = [:]
        let letters = ["A", "B", "C", "D", "E"]

        for item in pack?.items ?? [] {
            guard let sec = SectionCode(rawValue: item.section ?? "") else { continue }
            let topics = item.topic_ids ?? []
            switch item.kind {
            case "performance":
                let ch = item.choices ?? [:]
                let present = letters.filter { !(ch[$0] ?? "").isEmpty }
                guard !present.isEmpty else { continue }
                let choices = present.map { Choice(letter: $0, text: ch[$0] ?? "") }
                let correct = max(0, present.firstIndex(of: item.correct ?? "") ?? 0)
                let stem = item.question ?? ""
                qs.append(
                    Question(
                        section: sec, stem: stem, choices: choices,
                        correct: correct, explanation: item.explanation ?? "",
                        topicIds: topics,
                        key: mcatContentKey(["p", sec.rawValue, stem])))
                for t in topics { perf[sec, default: []].insert(t) }
            case "memory":
                let front = item.front ?? ""
                cards.append(
                    Flashcard(
                        front: front, back: item.back ?? "", section: sec,
                        topicIds: topics,
                        key: mcatContentKey(["m", sec.rawValue, front])))
                for t in topics { mem[sec, default: []].insert(t) }
            default:
                continue
            }
        }

        var taxTopics: [SectionCode: Set<String>] = [:]
        for (code, sectionData) in tax?.sections ?? [:] {
            guard let sec = SectionCode(rawValue: code) else { continue }
            taxTopics[sec] = Set(sectionData.topics.map { $0.id })
        }

        questions = qs
        flashcards = cards
        memoryTopics = mem
        perfTopics = perf
        taxonomyTopics = taxTopics
    }

    // MARK: - Access

    func questions(in sections: [SectionCode]) -> [Question] {
        let set = Set(sections)
        return questions.filter { set.contains($0.section) }
    }

    func flashcards(in sections: [SectionCode]) -> [Flashcard] {
        let set = Set(sections)
        return flashcards.filter { set.contains($0.section) }
    }

    /// Coverage as the engine expects it: {"bb":[covered,total], ...}.
    func coverageJSON() -> String {
        var map: [String: [Int]] = [:]
        for section in SectionCode.allCases {
            let c = coverage(section)
            map[section.rawValue] = [c.covered, c.total]
        }
        let data = (try? JSONSerialization.data(withJSONObject: map)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Coverage = share of the outline (taxonomy ∪ topics with a practice item)
    /// that has a performance item. Matches the desktop `_coverage`, and stays
    /// stable regardless of which flashcard set is loaded.
    func coverage(_ section: SectionCode) -> Coverage {
        let perf = perfTopics[section] ?? []
        let universe = (taxonomyTopics[section] ?? []).union(perf)
        let total = max(1, universe.count)
        let covered = universe.filter { perf.contains($0) }.count
        return Coverage(covered: covered, total: total, pct: Double(covered) / Double(total))
    }

    // MARK: - Decoding

    private static func decode<T: Decodable>(_ type: T.Type, resource: String) -> T? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private struct PackFile: Decodable { let items: [PackItem] }
    private struct PackItem: Decodable {
        let kind: String?
        let section: String?
        let topic_ids: [String]?
        let question: String?
        let choices: [String: String]?
        let correct: String?
        let explanation: String?
        let front: String?
        let back: String?
    }
    private struct TaxFile: Decodable { let sections: [String: TaxSection] }
    private struct TaxSection: Decodable { let topics: [TaxTopic] }
    private struct TaxTopic: Decodable { let id: String }
}
