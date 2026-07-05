// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Renders MCAT content markdown (the iOS twin of ts/routes/mcat/lib/markdown.ts):
// **bold**, unicode (NAD⁺, Cu²⁺, →), paragraphs, and GFM pipe tables. Tables get
// a real bordered layout inside a horizontal ScrollView so wide tables fit on a
// phone; on desktop-width they simply don't need to scroll.

import Foundation
import SwiftUI

/// Parse inline markdown (bold + unicode) into an AttributedString for a Text.
func mcatMarkdownAttr(_ s: String) -> AttributedString {
    (try? AttributedString(
        markdown: s,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(s)
}

struct MarkdownContent: View {
    let text: String
    var size: CGFloat = 16
    var weight: Font.Weight = .regular
    var centered: Bool = false

    private enum Block: Identifiable {
        case text(id: Int, String)
        case table(id: Int, [String], [[String]])
        var id: Int {
            switch self {
            case .text(let id, _): return id
            case .table(let id, _, _): return id
            }
        }
    }

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 10) {
            ForEach(blocks()) { block in
                switch block {
                case .text(_, let s):
                    Text(mcatMarkdownAttr(s))
                        .font(Theme.font(size, weight))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(centered ? .center : .leading)
                        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                case .table(_, let header, let rows):
                    tableView(header, rows)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }

    // MARK: - Table

    private func tableView(_ header: [String], _ rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                tableRow(header, isHeader: true, tint: Theme.surface2)
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    Divider()
                    tableRow(
                        row, isHeader: false,
                        tint: idx % 2 == 1 ? Theme.surface2.opacity(0.5) : Color.clear)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func tableRow(_ cells: [String], isHeader: Bool, tint: Color) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { j, cell in
                if j > 0 { Divider() }
                Text(mcatMarkdownAttr(cell))
                    .font(Theme.font(14, isHeader ? .bold : .regular))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(minWidth: 96, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(tint)
    }

    // MARK: - Parsing

    private func blocks() -> [Block] {
        let lines = text.components(separatedBy: "\n")
        var out: [Block] = []
        var para: [String] = []
        var id = 0

        func flush() {
            let joined = para.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                out.append(.text(id: id, joined))
                id += 1
            }
            para = []
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let next = i + 1 < lines.count ? lines[i + 1] : ""
            if line.contains("|") && isSeparator(next) {
                flush()
                let header = splitRow(line)
                i += 2
                var rows: [[String]] = []
                while i < lines.count && lines[i].contains("|") {
                    rows.append(splitRow(lines[i]))
                    i += 1
                }
                out.append(.table(id: id, header, rows))
                id += 1
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
                i += 1
                continue
            }
            para.append(line)
            i += 1
        }
        flush()
        return out
    }

    private func isSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-") else { return false }
        return t.allSatisfy { "|:- ".contains($0) }
    }

    private func splitRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }
}
