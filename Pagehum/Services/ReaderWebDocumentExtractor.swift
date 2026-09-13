// Modified for Pagehum: unified application and command-line naming.
import Foundation
import WebKit
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ReaderWebDocumentExtractor {
    private static let contentWorld = WKContentWorld.world(name: "PagehumReaderExtraction")

    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func extract(
        html: String,
        baseURL: URL,
        createdAt: Date = Date()
    ) async throws -> ReaderDocument {
        let webView = makeWebView()
        defer { detachFromHostWindow(webView) }
        try await load(webView) {
            webView.loadHTMLString(html, baseURL: baseURL)
        }
        return try await extractLoadedDocument(
            from: webView,
            originalURL: baseURL,
            finalURL: baseURL,
            createdAt: createdAt
        )
    }

    func extract(url: URL, createdAt: Date = Date()) async throws -> ReaderDocument {
        let webView = makeWebView()
        defer { detachFromHostWindow(webView) }
        try await load(webView) {
            webView.load(URLRequest(url: url))
        }
        return try await extractLoadedDocument(
            from: webView,
            originalURL: url,
            finalURL: webView.url ?? url,
            createdAt: createdAt
        )
    }

    // WKWebView navigation callbacks (`didFinish`) frequently never fire on iOS when the
    // view isn't attached to a window — many modern pages gate loading on visibility /
    // layout / IntersectionObserver signals that require a real view hierarchy. We host
    // the extractor's WebView inside a hidden 1×1 subview of the key window so the OS
    // treats it as a live view and delivers navigation events.
    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1024, height: 768),
            configuration: configuration
        )
        attachToHostWindow(webView)
        return webView
    }

    private func attachToHostWindow(_ webView: WKWebView) {
        #if canImport(UIKit)
        guard let host = Self.hostView() else { return }
        webView.isHidden = true
        webView.isUserInteractionEnabled = false
        webView.alpha = 0.0
        webView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        host.addSubview(webView)
        #endif
    }

    private func detachFromHostWindow(_ webView: WKWebView) {
        #if canImport(UIKit)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.removeFromSuperview()
        #endif
    }

    #if canImport(UIKit)
    private static func hostView() -> UIView? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first
        let window = activeScene?.windows.first(where: { $0.isKeyWindow })
            ?? activeScene?.windows.first
        return window?.rootViewController?.view ?? window
    }
    #endif

    private func load(_ webView: WKWebView, start: () -> Void) async throws {
        let waiter = ReaderNavigationWaiter()
        webView.navigationDelegate = waiter
        try await waiter.wait(timeout: .seconds(20), start: start)
    }

    private func extractLoadedDocument(
        from webView: WKWebView,
        originalURL: URL,
        finalURL: URL,
        createdAt: Date
    ) async throws -> ReaderDocument {
        _ = try await webView.callAsyncJavaScript(
            Self.quiescenceScript,
            arguments: [:],
            in: nil,
            contentWorld: Self.contentWorld
        )

        let script = try resourceScript(named: "Readability", extension: "js")
            + "\n"
            + resourceScript(named: "DOMPurify.min", extension: "js")
            + "\n"
            + Self.extractionScript
        guard let json = try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: Self.contentWorld
        ) as? String,
              let data = json.data(using: .utf8)
        else { throw ReaderWebDocumentExtractorError.invalidResult }

        let payload: ExtractionPayload
        do {
            payload = try JSONDecoder().decode(ExtractionPayload.self, from: data)
        } catch {
            throw ReaderWebDocumentExtractorError.invalidPayload(error.localizedDescription)
        }
        guard !payload.blocks.isEmpty else {
            throw ReaderWebDocumentExtractorError.noReadableContent
        }

          let projectedBlocks = payload.blocks.compactMap { block -> ReaderDocumentProjectedBlock? in
            guard let kind = ReaderDocumentBlock.Kind(rawValue: block.kind),
                  !block.text.isEmpty
            else { return nil }
            return ReaderDocumentProjectedBlock(
                id: block.id,
                kind: kind,
                isSpeakable: block.isSpeakable,
                text: block.text
            )
        }
        guard !projectedBlocks.isEmpty else {
            throw ReaderWebDocumentExtractorError.noReadableContent
        }

        let document = ReaderDocumentBuilder.webArticle(
            title: payload.title?.nilIfBlank ?? originalURL.host ?? "Web Page",
            articleHTML: payload.articleHTML,
            projectedBlocks: projectedBlocks,
            originalURL: originalURL,
            finalURL: finalURL,
            canonicalURL: payload.canonicalURL.flatMap(URL.init(string:)),
            byline: payload.byline?.nilIfBlank,
            siteName: payload.siteName?.nilIfBlank,
            excerpt: payload.excerpt?.nilIfBlank,
            language: payload.language?.nilIfBlank,
            direction: payload.direction?.nilIfBlank,
            publicationDate: payload.publicationDate?.nilIfBlank,
            createdAt: createdAt
        )
        try document.validateProjection()
        return document
    }

    private func resourceScript(named name: String, extension fileExtension: String) throws -> String {
        let url = bundle.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "ReaderScripts"
        ) ?? bundle.url(forResource: name, withExtension: fileExtension)
        guard let url else {
            throw ReaderWebDocumentExtractorError.missingScript("\(name).\(fileExtension)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private struct ExtractionPayload: Decodable {
        struct Block: Decodable {
            let id: String
            let kind: String
            let isSpeakable: Bool
            let text: String
        }

        let title: String?
        let byline: String?
        let siteName: String?
        let excerpt: String?
        let language: String?
        let direction: String?
        let publicationDate: String?
        let canonicalURL: String?
        let articleHTML: String
        let blocks: [Block]
    }

    private static let quiescenceScript = #"""
    const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
    const originalY = window.scrollY;
    const height = Math.max(document.documentElement.scrollHeight, document.body?.scrollHeight || 0);
    const step = Math.max(window.innerHeight, 600);
    for (let y = 0; y < height; y += step) {
        window.scrollTo(0, y);
        await delay(40);
    }
    window.scrollTo(0, originalY);

    return await new Promise(resolve => {
        let quietTimer;
        let hardTimer;
        const finish = reason => {
            clearTimeout(quietTimer);
            clearTimeout(hardTimer);
            observer.disconnect();
            resolve(reason);
        };
        const resetQuietTimer = () => {
            clearTimeout(quietTimer);
            quietTimer = setTimeout(() => finish('quiet'), 400);
        };
        const observer = new MutationObserver(resetQuietTimer);
        observer.observe(document.documentElement, {
            subtree: true,
            childList: true,
            attributes: true,
            characterData: true
        });
        hardTimer = setTimeout(() => finish('ceiling'), 3000);
        resetQuietTimer();
    });
    """#

    private static let extractionScript = #"""
    const parsed = new Readability(document.cloneNode(true), { charThreshold: 100 }).parse();
    if (!parsed || !parsed.content) {
        throw new Error('No readable content');
    }

    const sanitized = DOMPurify.sanitize(parsed.content, {
        ALLOWED_TAGS: [
            'article', 'section', 'main', 'div', 'span',
            'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p', 'br', 'hr',
            'em', 'strong', 'b', 'i', 'u', 's', 'del', 'ins', 'small',
            'sub', 'sup', 'mark', 'abbr', 'cite', 'q', 'blockquote',
            'pre', 'code', 'kbd', 'samp', 'var',
            'ul', 'ol', 'li', 'dl', 'dt', 'dd',
            'a', 'img', 'picture', 'source', 'figure', 'figcaption',
            'table', 'thead', 'tbody', 'tfoot', 'tr', 'th', 'td',
            'caption', 'colgroup', 'col', 'time'
        ],
        ALLOWED_ATTR: [
            'href', 'title', 'rel', 'target',
            'src', 'srcset', 'sizes', 'alt', 'width', 'height',
            'loading', 'decoding', 'lang', 'dir', 'datetime',
            'colspan', 'rowspan', 'scope'
        ],
        ALLOW_DATA_ATTR: false,
        ALLOW_ARIA_ATTR: false,
        SANITIZE_DOM: true,
        SANITIZE_NAMED_PROPS: true
    });

    const template = document.createElement('template');
    template.innerHTML = sanitized;
    const article = document.createElement('article');
    article.setAttribute('data-pagehum-schema-version', '1');
    article.appendChild(template.content);

    const selector = 'h1,h2,h3,h4,h5,h6,p,li,blockquote,pre,figcaption,table';
    const candidates = Array.from(article.querySelectorAll(selector)).filter(node => {
        for (let parent = node.parentElement; parent && parent !== article; parent = parent.parentElement) {
            if (parent.matches(selector)) return false;
        }
        return true;
    });
    if (candidates.length === 0) candidates.push(article);

    const BREAK = '\uE100';
    const CELL = '\uE101';
    const ROW = '\uE102';

    function kindFor(node) {
        const tag = node.tagName.toLowerCase();
        if (/^h[1-6]$/.test(tag)) return 'heading';
        if (tag === 'li') return 'listItem';
        if (tag === 'blockquote') return 'quote';
        if (tag === 'pre') return 'code';
        if (tag === 'figcaption') return 'imageCaption';
        if (tag === 'table') return 'table';
        return 'prose';
    }

    function projectedText(node, kind) {
        if (kind === 'code') {
            return (node.textContent || '')
                .replace(/\r\n?/g, '\n')
                .replace(/^\n+|\n+$/g, '');
        }

        function visit(current) {
            if (current.nodeType === Node.TEXT_NODE) return current.nodeValue || '';
            if (current.nodeType !== Node.ELEMENT_NODE) return '';
            const tag = current.tagName.toLowerCase();
            if (tag === 'br') return BREAK;

            let value = '';
            current.childNodes.forEach(child => { value += visit(child); });
            if (tag === 'th' || tag === 'td') value += CELL;
            if (tag === 'tr') value += ROW;
            return value;
        }

        return visit(node)
            .replace(/\s+/g, ' ')
            .replace(new RegExp(' *' + BREAK + ' *', 'g'), '\n')
            .replace(new RegExp(' *' + CELL + ' *', 'g'), '\t')
            .replace(new RegExp(' *' + ROW + ' *', 'g'), '\n')
            .replace(/\t+\n/g, '\n')
            .trim();
    }

    const blocks = [];
    candidates.forEach(node => {
        const kind = kindFor(node);
        const text = projectedText(node, kind);
        if (!text) return;
        const id = 'block-' + String(blocks.length + 1).padStart(6, '0');
        node.setAttribute('data-pagehum-block-id', id);
        blocks.push({ id, kind, isSpeakable: kind !== 'code', text });
    });

    const canonical = document.querySelector('link[rel~="canonical"]');
    return JSON.stringify({
        title: parsed.title || null,
        byline: parsed.byline || null,
        siteName: parsed.siteName || null,
        excerpt: parsed.excerpt || null,
        language: parsed.lang || document.documentElement.lang || null,
        direction: parsed.dir || document.documentElement.dir || null,
        publicationDate: parsed.publishedTime || null,
        canonicalURL: canonical ? canonical.href : null,
        articleHTML: article.outerHTML,
        blocks
    });
    """#
}

enum ReaderWebDocumentExtractorError: LocalizedError {
    case missingScript(String)
    case invalidResult
    case invalidPayload(String)
    case noReadableContent

    var errorDescription: String? {
        switch self {
        case .missingScript(let name):
            "Reader extraction resource is missing: \(name)."
        case .invalidResult:
            "Reader extraction returned an invalid result."
        case .invalidPayload(let reason):
            "Reader extraction returned invalid data: \(reason)"
        case .noReadableContent:
            "No readable text could be extracted from this page."
        }
    }
}

@MainActor
private final class ReaderNavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    func wait(timeout: Duration, start: () -> Void) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self?.finish(URLError(.timedOut))
                }
                start()
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in self?.finish(CancellationError()) }
        }
    }

    private func finish(_ error: Error? = nil) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(error)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
