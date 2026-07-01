// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Synthesized UI sounds (no audio files), matching the desktop web app:
//   click  — soft tap on button presses
//   start  — gentle ascending chime when a study screen opens (per activity)
//   streak — short celebratory fanfare when the daily path is completed
// Tones are generated as PCM buffers and played through AVAudioEngine. A mute
// flag mirrors the desktop's sound toggle.

import AVFoundation

final class SoundManager {
    static let shared = SoundManager()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate = 44_100.0
    private var started = false
    private var enabled = true

    private init() {}

    func setEnabled(_ on: Bool) { enabled = on }

    private func ensureStarted() {
        guard !started else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { /* non-fatal */ }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            player.play()
            started = true
        } catch { /* non-fatal */ }
    }

    /// notes: (frequencyHz, startSeconds, durationSeconds, peakAmplitude 0...1)
    private func play(_ notes: [(Double, Double, Double, Double)]) {
        guard enabled else { return }
        ensureStarted()
        guard started,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        else { return }
        let totalSec = (notes.map { $0.1 + $0.2 }.max() ?? 0) + 0.05
        let frames = AVAudioFrameCount(totalSec * sampleRate)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return }
        buffer.frameLength = frames
        guard let out = buffer.floatChannelData?[0] else { return }
        for i in 0..<Int(frames) { out[i] = 0 }

        for (freq, start, dur, peak) in notes {
            let s0 = Int(start * sampleRate)
            let n = Int(dur * sampleRate)
            let attack = 0.008 * sampleRate
            for k in 0..<n {
                let idx = s0 + k
                if idx < 0 || idx >= Int(frames) { continue }
                let t = Double(k)
                let env = t < attack ? (t / attack) : exp(-3.5 * (t - attack) / Double(max(n, 1)))
                out[idx] += Float(sin(2.0 * .pi * freq * (t / sampleRate)) * peak * env)
            }
        }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    func click() {
        play([(587.33, 0, 0.06, 0.34)])
    }

    /// Ascending major arpeggio; root shifts per activity kind.
    func start(_ kind: String) {
        let root: Double
        switch kind {
        case "memory": root = 523.25
        case "performance": root = 587.33
        case "cars": root = 659.25
        case "diagnostic": root = 493.88
        default: root = 523.25
        }
        let steps = [1.0, 1.25, 1.5, 2.0]
        var notes: [(Double, Double, Double, Double)] = []
        for (i, r) in steps.enumerated() {
            notes.append((root * r, Double(i) * 0.075, i == steps.count - 1 ? 0.34 : 0.2, 0.22))
        }
        play(notes)
    }

    /// Celebratory fanfare for completing the daily path / earning the streak.
    func streak() {
        var notes: [(Double, Double, Double, Double)] = []
        let rise = [523.25, 659.25, 783.99, 1046.5]
        for (i, f) in rise.enumerated() {
            notes.append((f, Double(i) * 0.1, 0.28, 0.26))
            notes.append((f * 2, Double(i) * 0.1, 0.28, 0.06))
        }
        let end = Double(rise.count) * 0.1 + 0.02
        for f in [1046.5, 1318.5, 1568.0] {
            notes.append((f, end, 0.5, 0.16))
        }
        play(notes)
    }
}
