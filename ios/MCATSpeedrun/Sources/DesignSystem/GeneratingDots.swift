// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// A small "the AI is working" indicator: three dots with a traveling highlight
// plus a label, shown while a concept diagram is being generated.

import SwiftUI

struct GeneratingDots: View {
    var label: String = "Generating diagram…"
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.28, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 10, height: 10)
                        .opacity(phase == i ? 1 : 0.35)
                        .scaleEffect(phase == i ? 1.25 : 1)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: phase)
            Text(label)
                .font(Theme.font(14, .bold))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface2))
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}
