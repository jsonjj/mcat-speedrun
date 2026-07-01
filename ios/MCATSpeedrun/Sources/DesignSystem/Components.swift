// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Reusable SwiftUI components shared across MCAT Speedrun screens. Screens
// should compose these rather than re-implementing surfaces/among themselves.

import SwiftUI

// MARK: - Surfaces

extension View {
    /// Standard rounded card surface. Pass a `tint` for an evidence-colored card.
    func cardStyle(tint: Color? = nil, padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface)
                    RoundedRectangle(cornerRadius: Theme.radius)
                        .fill((tint ?? .clear).opacity(0.10))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radius)
                    .stroke(tint == nil ? Theme.border : tint!.opacity(0.24), lineWidth: 1)
            }
    }

    /// Fills the whole screen with the themed background.
    func screenBackground() -> some View {
        self.background(Theme.bg.ignoresSafeArea())
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(16, .bold))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Theme.accent, Theme.accent2],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { SoundManager.shared.click() }
            }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(16, .semibold))
            .foregroundStyle(Theme.text)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(Theme.surface2)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { SoundManager.shared.click() }
            }
    }
}

extension View {
    /// Plays the tap click for non-Button tappables (cards, NavigationLinks).
    func tapSound() -> some View {
        self.simultaneousGesture(TapGesture().onEnded { SoundManager.shared.click() })
    }
}

/// Small labelled toggle chip used for the Dark Mode / Sound switches.
struct ToggleChip: View {
    var icon: String
    var label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14))
            Text(label).font(Theme.font(14, .semibold))
            Toggle("", isOn: $isOn).labelsHidden().scaleEffect(0.85).tint(Theme.accent)
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - Range bar

/// A value range on a fixed scale: a track, a tinted low–high band, and a tick.
struct RangeBarView: View {
    var lo: Double
    var hi: Double
    var low: Double
    var high: Double
    var point: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = Swift.max(hi - lo, 0.0001)
            let px = { (v: Double) in CGFloat((v - lo) / span) * w }
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track).frame(height: 6)
                Capsule().fill(color.opacity(0.55))
                    .frame(width: Swift.max(px(high) - px(low), 6), height: 6)
                    .offset(x: px(low))
                RoundedRectangle(cornerRadius: 2).fill(color)
                    .frame(width: 3, height: 15)
                    .offset(x: px(point) - 1.5)
            }
            .frame(height: 15)
        }
        .frame(height: 15)
    }
}

// MARK: - Evidence score card

struct EvidenceCardView: View {
    var title: String
    var icon: String
    var block: ScoreBlock
    var scaleMin: Double = 0
    var scaleMax: Double = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: icon).foregroundStyle(block.tone.color)
                Text(title).font(Theme.font(16, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Text(block.display).font(Theme.font(22, .heavy))
                    .foregroundStyle(block.tone.color)
            }
            RangeBarView(
                lo: scaleMin, hi: scaleMax,
                low: block.low ?? scaleMin, high: block.high ?? scaleMin,
                point: block.point ?? scaleMin, color: block.tone.color
            )
            HStack(spacing: 6) {
                Circle().fill(block.tone.color).frame(width: 7, height: 7)
                Text(block.abstained ? "Not enough evidence yet" : block.tone.label)
                    .font(Theme.font(13, .semibold)).foregroundStyle(block.tone.color)
            }
        }
        .cardStyle(tint: block.tone.color)
    }
}

// MARK: - Days ring

struct DaysRingView: View {
    var days: Int
    var progress: Double = 0.72

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: 8)
            Circle().trim(from: 0, to: progress)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(days)").font(Theme.font(30, .heavy)).foregroundStyle(Theme.text)
                Text("Days To Go").font(Theme.font(10, .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 128, height: 128)
    }
}

// MARK: - Small bits

struct Pill: View {
    var text: String
    var color: Color = Theme.muted
    var body: some View {
        Text(text)
            .font(Theme.font(12, .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

/// Section header used at the top of most screens.
struct ScreenHeader: View {
    var title: String
    var subtitle: String?
    init(_ title: String, _ subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Theme.font(28, .heavy)).foregroundStyle(Theme.text)
            if let subtitle {
                Text(subtitle).font(Theme.font(15, .semibold)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
