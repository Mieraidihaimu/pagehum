// Modified for Pagehum: unified application and command-line naming.
import Foundation
import Testing
import WebKit
@testable import Pagehum

@MainActor
struct WebReaderHighlightTests {

    @Test
    func readerModelBuildsContextAwareHighlightRequests() throws {
        let model = ReaderModel()
        let codePayload = try JSONSerialization.data(withJSONObject: ["v": 1, "l": "swift", "s": "let a = 1"])
        let codeMarker = "\(ArticleSegmenter.markerOpen)\(codePayload.base64EncodedString())\(ArticleSegmenter.markerClose)"
        let body = [
            "First intro sentence.",
            "Yes.",
            codeMarker,
            "After code sentence."
        ].joined(separator: "\n\n")
        model.prepareTextPublic(body)

        let first = model.highlightRequest(at: 0)
        #expect(first?.text == "First intro sentence.")
        #expect(first?.prevText == nil)
        #expect(first?.nextText == "Yes.")
        #expect(first?.blockKind == nil)

        let short = model.highlightRequest(at: 1)
        #expect(short?.text == "Yes.")
        #expect(short?.prevText == "First intro sentence.")
        // Adjacent code block announcement is skipped as prose context.
        #expect(short?.nextText == nil)

        let code = model.highlightRequest(at: 2)
        #expect(code?.text == "let a = 1")
        #expect(code?.blockKind == .code)
        #expect(code?.isBlockMode == true)
        #expect(code?.prevText == "Yes.")
        #expect(code?.nextText == "After code sentence.")
    }

    @Test
    func highlightsSentenceWithInlineTagsWithoutSelectingWholeArticle() async throws {
        let html = """
        <!doctype html>
        <html>
        <head><style>body { margin: 0; font: 16px/1.5 sans-serif; }</style></head>
        <body>
          <div id="article-shell">
            <nav><a href="#home">Home</a> <span>This intro sentence has inline markup right away.</span></nav>
            <article id="story">
              <p id="p1">Opening paragraph introduces the topic cleanly.</p>
              <p id="p2">This <a href="/link">intro <em>sentence</em></a> has <code>inline</code> <span>markup</span> right away and continues to the end.</p>
              <p id="p3">Closing paragraph wraps everything up.</p>
            </article>
          </div>
        </body>
        </html>
        """
        let harness = try await WebHighlightHarness(html: html)

        let req = HighlightPayload(
            text: "This intro sentence has inline markup right away and continues to the end.",
            prevText: "Opening paragraph introduces the topic cleanly.",
            nextText: "Closing paragraph wraps everything up.",
            progress: 0.5,
            blockKind: nil,
            isBlockMode: false,
            autoScroll: false
        )
        let inspection = try await harness.highlight(req)
        #expect(inspection.matched == true)
        #expect(inspection.highlightRangeCount == 1)
        #expect(inspection.activeBlockId == nil)
        #expect(inspection.shellHasActiveClass == false)
        #expect(inspection.rangeText == "This intro sentence has inline markup right away and continues to the end.")
        #expect(inspection.rangeStartBlockId == "p2")
        #expect(inspection.rangeHeight > 0 && inspection.rangeHeight < 200)

        try await harness.clear()
        let cleared = try await harness.inspect()
        #expect(cleared.highlightRangeCount == 0)
        #expect(cleared.activeBlockId == nil)
    }

    @Test
    func blockFallbackTargetsInnermostParagraphInsteadOfOuterDivWrapper() async throws {
        let html = """
        <!doctype html>
        <html>
        <body>
          <div id="article-shell">
            <div class="post-body">
              <div id="div-para-1">First <b>inline</b> paragraph inside nested divs.</div>
              <p id="p-target">Second <a href="#">nested link</a> paragraph with inline tags inside.</p>
            </div>
          </div>
        </body>
        </html>
        """
        let harness = try await WebHighlightHarness(html: html)

        // Force block-mode fallback on a prose paragraph to verify innermost block selection.
        let pResult = try await harness.highlight(HighlightPayload(
            text: "Second nested link paragraph with inline tags inside.",
            prevText: nil,
            nextText: nil,
            progress: 0.7,
            blockKind: nil,
            isBlockMode: true,
            autoScroll: false
        ))
        #expect(pResult.matched == true)
        #expect(pResult.activeBlockId == "p-target")
        #expect(pResult.shellHasActiveClass == false)

        let divResult = try await harness.highlight(HighlightPayload(
            text: "First inline paragraph inside nested divs.",
            prevText: nil,
            nextText: nil,
            progress: 0.2,
            blockKind: nil,
            isBlockMode: true,
            autoScroll: false
        ))
        #expect(divResult.matched == true)
        #expect(divResult.activeBlockId == "div-para-1")
        #expect(divResult.shellHasActiveClass == false)
    }

    @Test
    func disambiguatesShortAndDuplicateSentencesAndHandlesBackwardSeek() async throws {
        let html = """
        <!doctype html>
        <html>
        <body>
          <div style="display:none"><p id="hidden-dup">Yes.</p></div>
          <div style="overflow:hidden;width:1px;height:1px"><p id="sr-dup">Repeated line appears in the story.</p></div>
          <article>
            <p id="p-lead">First context before answer.</p>
            <p id="p-short-1">Yes.</p>
            <p id="p-mid-1">Repeated line appears in the story.</p>
            <p id="p-filler">A long middle paragraph separating two identical lines so progress distinguishes them clearly.</p>
            <p id="p-lead-2">Second context before answer.</p>
            <p id="p-short-2">Yes.</p>
            <p id="p-mid-2">Repeated line appears in the story.</p>
          </article>
        </body>
        </html>
        """
        let harness = try await WebHighlightHarness(html: html)

        // Short sentence matched in second position via prevText.
        let secondShort = try await harness.highlight(HighlightPayload(
            text: "Yes.",
            prevText: "Second context before answer.",
            nextText: "Repeated line appears in the story.",
            progress: 0.75,
            blockKind: nil,
            isBlockMode: false,
            autoScroll: false
        ))
        #expect(secondShort.matched == true)
        #expect(secondShort.rangeStartBlockId == "p-short-2")

        // Sequential advance finds second repeated line, not hidden/sr-only/first.
        let secondRepeat = try await harness.highlight(HighlightPayload(
            text: "Repeated line appears in the story.",
            prevText: "Yes.",
            nextText: nil,
            progress: 0.95,
            blockKind: nil,
            isBlockMode: false,
            autoScroll: false
        ))
        #expect(secondRepeat.matched == true)
        #expect(secondRepeat.rangeStartBlockId == "p-mid-2")

        // Scrubbing progress back to early in the article resolves to the first occurrence.
        let seekBack = try await harness.highlight(HighlightPayload(
            text: "Repeated line appears in the story.",
            prevText: "Yes.",
            nextText: nil,
            progress: 0.25,
            blockKind: nil,
            isBlockMode: false,
            autoScroll: false
        ))
        #expect(seekBack.matched == true)
        #expect(seekBack.rangeStartBlockId == "p-mid-1")
    }

    @Test
    func normalizesTypographyPrefersCodeAndTableBlocksAndRebuildsOnDOMMutation() async throws {
        let html = """
        <!doctype html>
        <html>
        <body>
          <article id="story">
            <p id="p-typo">“Smart\u{00A0}quotes”—and soft\u{00AD}hyphens—align<br>across lines.</p>
            <p id="p-inline-code">You can write <code>let value = 42</code> inline in prose.</p>
            <pre id="code-block"><code>let value = 42\nprint(value)</code></pre>
            <table id="data-table">
              <thead><tr><th>Language</th><th>Score</th></tr></thead>
              <tbody><tr><td>Swift</td><td>99</td></tr></tbody>
            </table>
          </article>
        </body>
        </html>
        """
        let harness = try await WebHighlightHarness(html: html)

        let typo = try await harness.highlight(HighlightPayload(
            text: "\"Smart quotes\"-and softhyphens-align across lines.",
            prevText: nil,
            nextText: nil,
            progress: 0.1,
            blockKind: nil,
            isBlockMode: false,
            autoScroll: false
        ))
        #expect(typo.matched == true)
        #expect(typo.rangeStartBlockId == "p-typo")

        let code = try await harness.highlight(HighlightPayload(
            text: "let value = 42",
            prevText: nil,
            nextText: nil,
            progress: 0.5,
            blockKind: "code",
            isBlockMode: true,
            autoScroll: false
        ))
        #expect(code.matched == true)
        #expect(code.activeBlockId == "code-block")

        let table = try await harness.highlight(HighlightPayload(
            text: "Language",
            prevText: nil,
            nextText: nil,
            progress: 0.8,
            blockKind: "table",
            isBlockMode: true,
            autoScroll: false
        ))
        #expect(table.matched == true)
        #expect(table.activeBlockId == "data-table")

        // Append a late paragraph and verify MutationObserver triggers index rebuild.
        try await harness.evaluate("""
        (() => {
          const p = document.createElement('p');
          p.id = 'late-p';
          p.textContent = 'Dynamically appended paragraph matches after load.';
          document.getElementById('story').appendChild(p);
        })()
        """)
        let late = try await harness.highlight(HighlightPayload(
            text: "Dynamically appended paragraph matches after load.",
            prevText: nil,
            nextText: nil,
            progress: 1.0,
            blockKind: nil,
            isBlockMode: false,
            autoScroll: false
        ))
        #expect(late.matched == true)
        #expect(late.rangeStartBlockId == "late-p")
    }
}

private struct HighlightPayload: Encodable {
    let text: String
    let prevText: String?
    let nextText: String?
    let progress: Double
    let blockKind: String?
    let isBlockMode: Bool
    let autoScroll: Bool
}

private struct HighlightInspection: Decodable {
    let matched: Bool
    let highlightRangeCount: Int
    let rangeText: String?
    let rangeStartBlockId: String?
    let rangeHeight: Double
    let activeBlockId: String?
    let shellHasActiveClass: Bool
}

@MainActor
private final class WebHighlightHarness: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, Error>?

    init(html: String) async throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        self.webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        super.init()
        webView.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            self.loadContinuation = continuation
            webView.loadHTMLString(html, baseURL: URL(string: "https://example.com/article"))
        }
        try await evaluate(WebReaderHighlightScript.source)
        try await evaluate("""
        window.__pagehumSetTheme({
          "--pagehum-sentence-bg": "rgba(14, 165, 233, 0.140)",
          "--pagehum-word-bg": "rgba(14, 165, 233, 0.250)",
          "--pagehum-word-text": "rgba(0, 0, 0, 1.000)",
          "--pagehum-appearance": "light"
        })
        """)
    }

    func highlight(_ payload: HighlightPayload) async throws -> HighlightInspection {
        let data = try JSONEncoder().encode(payload)
        let json = try #require(String(data: data, encoding: .utf8))
        let script = """
        (() => {
          const matched = !!window.__pagehumHighlight(\(json));
          const hl = (typeof CSS !== 'undefined' && CSS.highlights) ? CSS.highlights.get('pagehum-current') : null;
          const ranges = hl ? Array.from(hl) : [];
          const range = ranges[0] || null;
          const startEl = range
            ? (range.startContainer.nodeType === 3 ? range.startContainer.parentElement : range.startContainer)
            : null;
          const blockEl = startEl ? startEl.closest('p, div[id], pre, table, li, blockquote, h1, h2, h3') : null;
          const activeEl = document.querySelector('.pagehum-active-block');
          const shell = document.getElementById('article-shell');
          const rect = range ? range.getBoundingClientRect() : null;
          return JSON.stringify({
            matched: matched,
            highlightRangeCount: ranges.length,
            rangeText: range ? range.toString() : null,
            rangeStartBlockId: blockEl ? blockEl.id : null,
            rangeHeight: rect ? rect.height : 0,
            activeBlockId: activeEl ? (activeEl.id || activeEl.tagName) : null,
            shellHasActiveClass: !!(shell && shell.classList.contains('pagehum-active-block'))
          });
        })()
        """
        let raw = try await evaluate(script) as? String
        let rawData = try #require(raw?.data(using: .utf8))
        return try JSONDecoder().decode(HighlightInspection.self, from: rawData)
    }

    func inspect() async throws -> HighlightInspection {
        let script = """
        (() => {
          const hl = (typeof CSS !== 'undefined' && CSS.highlights) ? CSS.highlights.get('pagehum-current') : null;
          const ranges = hl ? Array.from(hl) : [];
          const activeEl = document.querySelector('.pagehum-active-block');
          const shell = document.getElementById('article-shell');
          return JSON.stringify({
            matched: ranges.length > 0 || !!activeEl,
            highlightRangeCount: ranges.length,
            rangeText: null,
            rangeStartBlockId: null,
            rangeHeight: 0,
            activeBlockId: activeEl ? (activeEl.id || activeEl.tagName) : null,
            shellHasActiveClass: !!(shell && shell.classList.contains('pagehum-active-block'))
          });
        })()
        """
        let raw = try await evaluate(script) as? String
        let rawData = try #require(raw?.data(using: .utf8))
        return try JSONDecoder().decode(HighlightInspection.self, from: rawData)
    }

    func clear() async throws {
        try await evaluate("window.__pagehumClear()")
    }

    @discardableResult
    func evaluate(_ script: String) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }
}
