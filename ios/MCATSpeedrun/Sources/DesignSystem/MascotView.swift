// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// A small friendly robot mascot used in the question-review flow — the iOS twin
// of ts/routes/mcat/lib/Mascot.svelte. Drawn with Canvas so it scales cleanly.

import SwiftUI

struct MascotView: View {
    enum Mood { case happy, neutral }
    var size: CGFloat = 96
    var mood: Mood = .happy
    var color: Color = Color(red: 0.357, green: 0.357, blue: 0.839)  // #5b5bd6

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = canvasSize.width / 120.0
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s))
            }

            let orange = Color(red: 0.949, green: 0.639, blue: 0.235)
            let dark = Color(red: 0.122, green: 0.137, blue: 0.251)

            var a1 = Path(); a1.move(to: pt(42, 27)); a1.addLine(to: pt(37, 12))
            ctx.stroke(a1, with: .color(color), style: StrokeStyle(lineWidth: 4 * s, lineCap: .round))
            var a2 = Path(); a2.move(to: pt(78, 27)); a2.addLine(to: pt(83, 12))
            ctx.stroke(a2, with: .color(color), style: StrokeStyle(lineWidth: 4 * s, lineCap: .round))
            ctx.fill(dot(36, 10, 5), with: .color(orange))
            ctx.fill(dot(84, 10, 5), with: .color(orange))

            ctx.fill(
                Path(roundedRect: CGRect(x: 22 * s, y: 26 * s, width: 76 * s, height: 70 * s),
                     cornerRadius: 26 * s), with: .color(color))
            ctx.fill(
                Path(roundedRect: CGRect(x: 35 * s, y: 47 * s, width: 20 * s, height: 27 * s),
                     cornerRadius: 10 * s), with: .color(.white))
            ctx.fill(
                Path(roundedRect: CGRect(x: 65 * s, y: 47 * s, width: 20 * s, height: 27 * s),
                     cornerRadius: 10 * s), with: .color(.white))
            ctx.fill(dot(46, 61, 5.5), with: .color(dark))
            ctx.fill(dot(74, 61, 5.5), with: .color(dark))

            var smile = Path()
            if mood == .happy {
                smile.move(to: pt(45, 82)); smile.addQuadCurve(to: pt(75, 82), control: pt(60, 93))
            } else {
                smile.move(to: pt(48, 85)); smile.addLine(to: pt(72, 85))
            }
            ctx.stroke(smile, with: .color(.white), style: StrokeStyle(lineWidth: 4 * s, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}
