// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Renders a (already sanitized) inline SVG string for the question-review
// concept diagrams. Uses WKWebView with JavaScript disabled — static vector
// only — so it's the visual twin of the desktop's inline {@html svg}.

import SwiftUI
import WebKit

struct SVGWebView: UIViewRepresentable {
    let svg: String
    /// Hex color the SVG's `currentColor` resolves to (axes + labels), so the
    /// figure reads on the current theme. Accent hex in the SVG stay as-is.
    var textColor: String = "#1F2340"

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
          html, body { margin: 0; padding: 0; background: transparent; color: \(textColor); }
          .wrap { display: flex; align-items: center; justify-content: center; height: 100vh; padding: 4px; box-sizing: border-box; }
          svg { max-width: 100%; max-height: 100%; height: auto; }
        </style></head>
        <body><div class="wrap">\(svg)</div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
