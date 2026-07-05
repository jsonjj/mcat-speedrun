// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// A tiny, safe markdown renderer for MCAT content (questions, choices,
// explanations, flashcards). The content pack authors passages in markdown —
// GFM pipe tables, **bold**, and unicode (NAD⁺, Cu²⁺, →, µmol·min⁻¹). We render
// only that subset. Everything is HTML-escaped FIRST, so the output is safe to
// inject with {@html} (we never emit tags from the source, only from our own
// wrappers).

function escapeHtml(s: string): string {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// Inline: **bold** (source is already HTML-escaped).
function inline(s: string): string {
    return s.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
}

function splitRow(line: string): string[] {
    let s = line.trim();
    if (s.startsWith("|")) {
        s = s.slice(1);
    }
    if (s.endsWith("|")) {
        s = s.slice(0, -1);
    }
    return s.split("|").map((c) => c.trim());
}

function isSeparator(line: string): boolean {
    // e.g. |---|---|  or  ---|:--:|--
    return /-/.test(line) && /^[\s|:-]+$/.test(line.trim());
}

/** Render a subset of markdown (bold, GFM tables, paragraphs) to safe HTML. */
export function renderContent(raw: string | null | undefined): string {
    const text = raw ?? "";
    if (!text.trim()) {
        return "";
    }
    const lines = escapeHtml(text).split("\n");
    const out: string[] = [];
    let para: string[] = [];

    function flushPara(): void {
        if (para.length) {
            out.push(`<p>${inline(para.join(" "))}</p>`);
            para = [];
        }
    }

    let i = 0;
    while (i < lines.length) {
        const line = lines[i];
        const hasPipe = line.includes("|");
        const next = i + 1 < lines.length ? lines[i + 1] : "";
        // A GFM table: a header row of pipes, then a separator row.
        if (hasPipe && isSeparator(next)) {
            flushPara();
            const header = splitRow(line);
            i += 2;
            const rows: string[][] = [];
            while (i < lines.length && lines[i].includes("|")) {
                rows.push(splitRow(lines[i]));
                i += 1;
            }
            let t = '<div class="md-table-wrap"><table class="md-table"><thead><tr>';
            t += header.map((h) => `<th>${inline(h)}</th>`).join("");
            t += "</tr></thead><tbody>";
            for (const r of rows) {
                t += "<tr>" + r.map((c) => `<td>${inline(c)}</td>`).join("") + "</tr>";
            }
            t += "</tbody></table></div>";
            out.push(t);
            continue;
        }
        if (line.trim() === "") {
            flushPara();
            i += 1;
            continue;
        }
        para.push(line);
        i += 1;
    }
    flushPara();
    return out.join("");
}
