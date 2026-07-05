// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Tiny trend sparkline for the account score cards. Values are percents; the
// line is scaled to its own min/max so small real movements stay visible, and
// it draws itself in on appear.

import SwiftUI

struct Sparkline: View {
    var points: [Double]
    var color: Color

    @State private var drawn = false
    private let pad: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if points.count > 1 {
                    areaPath(in: geo.size).fill(color.opacity(0.12))
                    linePath(in: geo.size)
                        .trim(from: 0, to: drawn ? 1 : 0)
                        .stroke(
                            color,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    Circle().fill(color).frame(width: 5, height: 5)
                        .position(point(points.count - 1, in: geo.size))
                        .opacity(drawn ? 1 : 0)
                }
            }
            .onAppear { withAnimation(.easeOut(duration: 0.8)) { drawn = true } }
        }
        .frame(height: 30)
    }

    private func point(_ i: Int, in size: CGSize) -> CGPoint {
        let lo = points.min() ?? 0
        let hi = points.max() ?? 100
        let span = max(1, hi - lo)
        let x =
            points.count > 1
            ? CGFloat(i) / CGFloat(points.count - 1) * (size.width - pad * 2) + pad : pad
        let y = size.height - pad - CGFloat((points[i] - lo) / span) * (size.height - pad * 2)
        return CGPoint(x: x, y: y)
    }

    private func linePath(in size: CGSize) -> Path {
        var p = Path()
        guard points.count > 1 else { return p }
        p.move(to: point(0, in: size))
        for i in points.indices.dropFirst() { p.addLine(to: point(i, in: size)) }
        return p
    }

    private func areaPath(in size: CGSize) -> Path {
        var p = Path()
        guard points.count > 1 else { return p }
        p.move(to: CGPoint(x: pad, y: size.height))
        for i in points.indices { p.addLine(to: point(i, in: size)) }
        p.addLine(to: CGPoint(x: size.width - pad, y: size.height))
        p.closeSubpath()
        return p
    }
}
