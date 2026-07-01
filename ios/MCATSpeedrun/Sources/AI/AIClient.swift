// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// AI layer for MCAT Speedrun (OpenAI) — the iOS twin of pylib/anki/mcat/ai.py.
// Same model, same prompts, same NAMED-SOURCE grounding, so desktop and iOS give
// the same kind of feedback. Design rules (identical to the desktop):
//
// - Gated: callers only invoke this when `app.aiEnabled` is true. With AI off,
//   the app behaves exactly as the no-AI build.
// - Grounded: every prompt carries a named source (the question's own
//   explanation, the passage text, the measured scores), surfaced back to the UI
//   as `source` so each output is traceable.
// - Fail-safe: any network/timeout/parse error returns nil. The UI falls back to
//   the deterministic non-AI experience; AI never blocks or crashes a session.
// - Cheap + offline-friendly: responses are cached (UserDefaults) by a hash of
//   model+prompt, so re-opening a review doesn't re-bill the API.
//
// NOTE: the key is read from a bundled, gitignored file (dev only). A production
// build would route through a server proxy instead of shipping the key.

import CryptoKit
import Foundation

enum AIClient {
    static let model = "gpt-4o-mini"  // matches ai.py
    private static let apiURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let timeout: TimeInterval = 30

    // MARK: - Key + availability

    /// Load the OpenAI key from (in order): the OPENAI_API_KEY env var, an
    /// Info.plist value, or the bundled gitignored openai_key.txt resource.
    static func apiKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            let trimmed = env.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String,
            !plist.isEmpty
        {
            return plist
        }
        if let url = Bundle.main.url(forResource: "openai_key", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// True when an API key is configured (independent of the user toggle).
    static var available: Bool { apiKey() != nil }

    // MARK: - Low-level chat + cache

    private static func cacheGet(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }
    private static func cachePut(_ key: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func cacheKey(_ system: String, _ user: String) -> String {
        let raw = "\(model)\u{1f}\(system)\u{1f}\(user)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return "ai.cache." + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// One chat completion. Returns the assistant text, or nil on any failure.
    private static func chat(
        system: String, user: String, wantJSON: Bool, cache: Bool
    ) async -> String? {
        guard let key = apiKey() else { return nil }

        var ck = ""
        if cache {
            ck = cacheKey(system, user)
            if let hit = cacheGet(ck), !hit.isEmpty { return hit }
        }

        var payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": 0.3,
            "max_tokens": 700,
        ]
        if wantJSON { payload["response_format"] = ["type": "json_object"] }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }

        var req = URLRequest(url: apiURL, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = body

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            guard
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = obj["choices"] as? [[String: Any]],
                let message = choices.first?["message"] as? [String: Any],
                let content = message["content"] as? String
            else { return nil }
            if cache, !content.isEmpty { cachePut(ck, content) }
            return content
        } catch {
            return nil
        }
    }

    private static func chatJSON(system: String, user: String) async -> [String: Any]? {
        guard let text = await chat(system: system, user: user, wantJSON: true, cache: true)
        else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    private static func str(_ any: Any?) -> String {
        (any as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Feature: reasoning feedback on a performance question

    /// Grade a student's free-response reasoning against the question's own
    /// explanation (the NAMED SOURCE). Returns feedback, or nil if AI is
    /// unavailable (caller falls back to just showing the explanation).
    static func gradeReasoning(
        question: String, choices: [Choice], studentChoice: String,
        correctChoice: String, explanation: String, studentReasoning: String
    ) async -> AiFeedback? {
        let choiceLines = choices.map { "\($0.letter). \($0.text)" }.joined(separator: "\n")
        let system =
            "You are an MCAT tutor giving short, specific feedback on a student's "
            + "reasoning. Judge ONLY against the provided official explanation — do not "
            + "invent facts. Be encouraging but honest. Respond as JSON with keys: "
            + "verdict (one of 'sound','partially_sound','flawed'), feedback (2-3 "
            + "sentences addressed to the student), key_point (the single most "
            + "important idea they should take away)."
        let user =
            "QUESTION:\n\(question)\n\nCHOICES:\n\(choiceLines)\n\n"
            + "STUDENT'S ANSWER: \(studentChoice.isEmpty ? "(none)" : studentChoice)\n"
            + "CORRECT ANSWER: \(correctChoice)\n"
            + "OFFICIAL EXPLANATION (your source of truth):\n\(explanation)\n\n"
            + "STUDENT'S REASONING:\n"
            + (studentReasoning.isEmpty ? "(they did not explain)" : studentReasoning)
        guard let out = await chatJSON(system: system, user: user) else { return nil }
        return AiFeedback(
            verdict: str(out["verdict"]),
            feedback: str(out["feedback"]),
            keyPoint: str(out["key_point"]),
            source: "Official answer explanation")
    }

    // MARK: - Feature: personalized study coach

    /// Recommend the single best next step from the student's measured scores.
    /// `factsJSON` is the compact scores summary built by Scoring (the named
    /// source). Returns a recommendation, or nil on failure.
    static func coachRecommendation(factsJSON: String) async -> CoachRecommendation? {
        let system =
            "You are an MCAT study coach. From the student's measured scores, pick the "
            + "single most useful next action. Numbers: memory and performance are "
            + "percents (0-100); coverage_pct is 0-1; readiness is a section/total score "
            + "or null when not yet estimated. Apply these rules IN ORDER and stop at the "
            + "first that fits:\n"
            + "1) If coverage is thin (most sections' coverage_pct below ~0.40) while "
            + "recall and accuracy are otherwise okay, focus='coverage'.\n"
            + "2) If OVERALL memory recall is weak (below ~70) or not yet measured "
            + "(null), focus='memory'. CARS has no flashcards, so its null memory is "
            + "normal — judge memory by the overall number and the science sections.\n"
            + "3) If memory is solid but one section's performance clearly lags the "
            + "others, focus='performance' and set section to that section's code.\n"
            + "4) If overall recall, accuracy and coverage are all strong (e.g. memory "
            + ">= ~80 and performance >= ~75 with healthy coverage), focus='balanced'.\n"
            + "Also consider pacing: pacing_slow_pct is the share of recent questions "
            + "answered past the time limit; when it's high (above ~30), work a brief "
            + "note to practice under time pressure into the detail, whatever the focus.\n"
            + "Prefer prerequisite flashcards for memory/coverage; targeted question sets "
            + "for performance. Respond as JSON with keys: focus (one of "
            + "'memory','performance','coverage','balanced'), section (a section code "
            + "'bb','cp','ps','cars' or ''), headline (<=8 words), detail (2 sentences, "
            + "specific and actionable)."
        let user = "STUDENT SCORES (your source):\n\(factsJSON)"
        guard let out = await chatJSON(system: system, user: user) else { return nil }
        return CoachRecommendation(
            focus: str(out["focus"]).isEmpty ? "balanced" : str(out["focus"]),
            section: str(out["section"]),
            headline: str(out["headline"]),
            detail: str(out["detail"]),
            source: "Your measured scores")
    }

    // MARK: - Feature: CARS debate

    /// Respond in a CARS debate as the author defending their claim, grounded in
    /// the passage text (the named source). `history` is [(role, content)].
    static func carsDebateReply(
        passage: String, authorClaim: String,
        history: [(role: String, content: String)], studentMessage: String
    ) async -> CarsDebateReply? {
        let system =
            "You are role-playing the AUTHOR of an MCAT CARS passage in a debate with "
            + "a student. Defend the passage's argument using ONLY reasoning and evidence "
            + "grounded in the passage — never outside facts. Push back on weak points, "
            + "concede genuinely strong ones, and keep it to 2-4 sentences. Then, "
            + "separately, give a brief coaching note on the quality of the student's "
            + "reasoning. Respond as JSON with keys: reply (the author's rebuttal), "
            + "critique (1 sentence on the student's reasoning skill), "
            + "skill (one CARS skill being exercised)."
        let convo = history.suffix(6).map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        let user =
            "PASSAGE (your source of truth):\n\(passage)\n\n"
            + "AUTHOR'S CENTRAL CLAIM: \(authorClaim)\n\n"
            + "DEBATE SO FAR:\n\(convo.isEmpty ? "(start)" : convo)\n\n"
            + "STUDENT'S LATEST ARGUMENT:\n\(studentMessage)"
        // Debate turns are conversational, so don't cache them.
        guard let text = await chat(system: system, user: user, wantJSON: true, cache: false),
            let out = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        else { return nil }
        return CarsDebateReply(
            reply: str(out["reply"]),
            critique: str(out["critique"]),
            skill: str(out["skill"]),
            source: "Passage text")
    }
}
