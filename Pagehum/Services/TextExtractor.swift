import Foundation
import PDFKit
import WebKit

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

@MainActor
protocol ContentExtracting: AnyObject {
    func extract(from source: ContentSource) async throws -> ReadingContent
}

@MainActor
final class TextExtractor: ContentExtracting {

    private var webView: WKWebView?
    private let webDocumentExtractor = ReaderWebDocumentExtractor()

    func extract(from source: ContentSource) async throws -> ReadingContent {
        switch source {
        case .url(let url):
            return try await extractFromWeb(url)
        case .pdf(let url):
            return try await extractFromPDF(url)
        case .text(let text):
            let document = ReaderDocumentBuilder.pastedText(title: "Pasted Text", text: text)
            return ReadingContent(
                title: document.manifest.title,
                body: document.plainText,
                source: source,
                readerDocument: document
            )
        }
    }

    private func extractFromWeb(_ url: URL) async throws -> ReadingContent {
        let document = try await webDocumentExtractor.extract(url: url)
        return ReadingContent(
            title: document.manifest.title,
            body: document.plainText,
            source: .url(url),
            byline: document.manifest.byline,
            siteName: document.manifest.siteName,
            readerDocument: document
        )
    }

    // Readability-style article extraction — scores DOM nodes by text density
    // to isolate the main content, similar to Safari Reader Mode.
    //
    // Code blocks (`<pre>`) are replaced with `ArticleSegmenter` sentinel markers rather than being
    // inlined as prose — otherwise Kokoro reads stack traces and `=>` operators aloud. The marker
    // delimiters are interpolated from `ArticleSegmenter` so the two sides cannot drift.
    private static let readerJS = """
    (function() {
        var MARK_OPEN = '\(ArticleSegmenter.jsMarkerOpen)';
        var MARK_CLOSE = '\(ArticleSegmenter.jsMarkerClose)';
        var MARK_VERSION = \(ArticleSegmenter.formatVersion);
        var MAX_CODE_LENGTH = \(ArticleSegmenter.maxSourceLength);
        var UNLIKELY = /banner|breadcrumb|combx|comment|community|cover-wrap|disqus|extra|footer|gdpr|header|legends|menu|related|remark|replies|rss|shoutbox|sidebar|skyscraper|social|sponsor|supplemental|ad-break|agegate|pagination|pager|popup|yom-hierarchical-nav|consent|cookie|newsletter|signup|subscribe|promo|widget|share|toolbar|nav/i;
        var POSITIVE = /article|body|content|entry|hentry|h-entry|main|page|pagination|post|text|blog|story/i;
        var NEGATIVE = /hidden|^hid$|hid$|hid|^hid |banner|combx|comment|com-|contact|foot|footer|footnote|gdpr|masthead|media|meta|outbrain|promo|related|scroll|share|shoutbox|sidebar|skyscraper|sponsor|shopping|tags|tool|widget|cookie|consent|newsletter|signup|subscribe/i;

        function getByline() {
            var metas = [
                'meta[name="author"]', 'meta[property="author"]',
                'meta[name="article:author"]', 'meta[property="article:author"]',
                '[rel="author"]', '.author', '.byline', '[itemprop="author"]'
            ];
            for (var i = 0; i < metas.length; i++) {
                var el = document.querySelector(metas[i]);
                if (el) {
                    var val = el.content || el.textContent || '';
                    val = val.trim();
                    if (val.length > 0 && val.length < 100) return val;
                }
            }
            return '';
        }

        function getSiteName() {
            var el = document.querySelector('meta[property="og:site_name"]');
            return el ? (el.content || '').trim() : '';
        }

        function getTitle() {
            var og = document.querySelector('meta[property="og:title"]');
            if (og && og.content) return og.content.trim();
            var h1 = document.querySelector('article h1, .article h1, .post h1, h1');
            if (h1 && h1.textContent.trim().length > 10) return h1.textContent.trim();
            return document.title || '';
        }

        function stripUnlikely(root) {
            var toRemove = [];
            root.querySelectorAll('*').forEach(function(el) {
                var tag = el.tagName.toLowerCase();
                if (tag === 'body' || tag === 'article' || tag === 'main') return;
                var cls = (el.className || '') + ' ' + (el.id || '');
                if (UNLIKELY.test(cls) && !POSITIVE.test(cls)) {
                    toRemove.push(el);
                }
            });
            toRemove.forEach(function(el) { if (el.parentNode) el.parentNode.removeChild(el); });
        }

        function scoreNode(node) {
            var score = 0;
            var tag = node.tagName.toLowerCase();
            if (['div','article','section','main'].indexOf(tag) >= 0) score += 5;
            else if (['pre','td','blockquote'].indexOf(tag) >= 0) score += 3;
            else if (['form','ul','ol','dl'].indexOf(tag) >= 0) score -= 3;
            else if (['body'].indexOf(tag) >= 0) score -= 5;

            var cls = (node.className || '') + ' ' + (node.id || '');
            if (POSITIVE.test(cls)) score += 25;
            if (NEGATIVE.test(cls)) score -= 25;
            return score;
        }

        function textLength(el) {
            return (el.textContent || '').trim().length;
        }

        function linkDensity(el) {
            var tl = textLength(el);
            if (tl === 0) return 1;
            var linkLen = 0;
            el.querySelectorAll('a').forEach(function(a) { linkLen += textLength(a); });
            return linkLen / tl;
        }

        function findBestNode(root) {
            var candidates = new Map();
            var paragraphs = root.querySelectorAll('p, pre, blockquote, td');
            for (var i = 0; i < paragraphs.length; i++) {
                var p = paragraphs[i];
                var txt = (p.textContent || '').trim();
                if (txt.length < 25) continue;

                var parent = p.parentNode;
                var grandParent = parent ? parent.parentNode : null;
                if (!parent || parent.nodeType !== 1) continue;

                if (!candidates.has(parent)) {
                    candidates.set(parent, scoreNode(parent));
                }
                if (grandParent && grandParent.nodeType === 1 && !candidates.has(grandParent)) {
                    candidates.set(grandParent, scoreNode(grandParent));
                }

                var contentScore = 1;
                contentScore += txt.split(',').length;
                contentScore += Math.min(Math.floor(txt.length / 100), 3);

                candidates.set(parent, (candidates.get(parent) || 0) + contentScore);
                if (grandParent && candidates.has(grandParent)) {
                    candidates.set(grandParent, (candidates.get(grandParent) || 0) + contentScore / 2);
                }
            }

            var best = null;
            var bestScore = -Infinity;
            candidates.forEach(function(score, node) {
                score = score * (1 - linkDensity(node));
                if (score > bestScore) {
                    bestScore = score;
                    best = node;
                }
            });
            return best;
        }

        // Self-contained UTF-8 → base64. Deliberately does NOT use btoa/TextEncoder: btoa throws on
        // non-Latin1 (code comments contain unicode), the String.fromCharCode.apply workaround has an
        // argument-count ceiling on large blocks, and a throw here would silently drop the code block
        // rather than degrade. This has no host dependencies and cannot fail.
        var B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

        function b64(str) {
            var bytes = [];
            for (var i = 0; i < str.length; i++) {
                var c = str.charCodeAt(i);
                if (c < 0x80) {
                    bytes.push(c);
                } else if (c < 0x800) {
                    bytes.push(0xC0 | (c >> 6), 0x80 | (c & 63));
                } else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < str.length
                           && str.charCodeAt(i + 1) >= 0xDC00 && str.charCodeAt(i + 1) <= 0xDFFF) {
                    // Surrogate pair → single 4-byte code point (emoji in comments).
                    var cp = 0x10000 + ((c - 0xD800) << 10) + (str.charCodeAt(i + 1) - 0xDC00);
                    i++;
                    bytes.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 63), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
                } else if (c >= 0xD800 && c <= 0xDFFF) {
                    // Lone surrogate → U+FFFD, so the payload stays valid UTF-8 and still decodes.
                    bytes.push(0xEF, 0xBF, 0xBD);
                } else {
                    bytes.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
                }
            }

            var out = '';
            for (var j = 0; j < bytes.length; j += 3) {
                var b0 = bytes[j];
                var b1 = j + 1 < bytes.length ? bytes[j + 1] : -1;
                var b2 = j + 2 < bytes.length ? bytes[j + 2] : -1;
                out += B64_CHARS.charAt(b0 >> 2);
                out += B64_CHARS.charAt(((b0 & 3) << 4) | (b1 < 0 ? 0 : b1 >> 4));
                out += b1 < 0 ? '=' : B64_CHARS.charAt(((b1 & 15) << 2) | (b2 < 0 ? 0 : b2 >> 6));
                out += b2 < 0 ? '=' : B64_CHARS.charAt(b2 & 63);
            }
            return out;
        }

        // Best-effort language token from the highlighter's markup: Prism/Shiki (language-x),
        // Rouge/Pygments (highlight-x, .highlight wrapper), Pandoc (.sourceCode), data-lang.
        function detectLanguage(pre) {
            var candidates = [pre];
            var code = pre.querySelector('code');
            if (code) candidates.push(code);
            var wrapper = pre.closest ? pre.closest('.highlight, .codehilite, .sourceCode, .code-block, [class*="language-"], [data-lang]') : null;
            if (wrapper) candidates.push(wrapper);

            for (var i = 0; i < candidates.length; i++) {
                var el = candidates[i];
                if (!el || !el.getAttribute) continue;

                var attrs = ['data-lang', 'data-language', 'lang'];
                for (var a = 0; a < attrs.length; a++) {
                    var v = el.getAttribute(attrs[a]);
                    if (v && v.trim()) return v.trim().toLowerCase();
                }

                // className is an SVGAnimatedString on SVG elements — normalize to a plain string.
                var cls = el.className;
                if (cls && typeof cls === 'object' && 'baseVal' in cls) cls = cls.baseVal;
                var clsStr = String(cls || '');

                // GitHub: highlight-source-cpp, highlight-text-html-basic. Must run before the
                // generic pattern below, which would otherwise capture "source" as the language.
                var gh = clsStr.match(/highlight-(?:source|text)-([a-z0-9+#-]+)/i);
                if (gh) return gh[1].toLowerCase().split('-')[0];

                // Prism / Shiki / Rouge / SyntaxHighlighter.
                var m = clsStr.match(/(?:language|lang|highlight|brush)[-:]([a-z0-9+#]+)/i);
                if (m && m[1].toLowerCase() !== 'source' && m[1].toLowerCase() !== 'text') {
                    return m[1].toLowerCase();
                }

                // Pandoc: <pre class="sourceCode swift">.
                if (/(^|\\s)sourceCode(\\s|$)/.test(clsStr)) {
                    var tokens = clsStr.split(/\\s+/);
                    for (var t = 0; t < tokens.length; t++) {
                        var tok = tokens[t].toLowerCase();
                        if (tok && tok !== 'sourcecode' && tok !== 'numberlines') return tok;
                    }
                }
            }
            return null;
        }

        // Swap every outermost <pre> for a sentinel marker carrying its source, so the code is
        // lifted out of the spoken stream instead of being read aloud character by character.
        // Inline <code> in prose is deliberately left alone — it is part of the sentence.
        function markCodeBlocks(root) {
            var blocks = [];
            root.querySelectorAll('pre').forEach(function(pre) {
                // Outermost only: skip a <pre> nested inside another <pre>.
                if (pre.parentElement && pre.parentElement.closest && pre.parentElement.closest('pre')) return;
                blocks.push(pre);
            });

            blocks.forEach(function(pre) {
                if (!pre.parentNode) return;
                var source = pre.textContent || '';
                if (!source.trim()) { pre.remove(); return; }
                if (source.length > MAX_CODE_LENGTH) source = source.substring(0, MAX_CODE_LENGTH);

                var marker;
                try {
                    marker = MARK_OPEN + b64(JSON.stringify({
                        v: MARK_VERSION, l: detectLanguage(pre), s: source
                    })) + MARK_CLOSE;
                } catch (e) {
                    // Encoding failed — drop the code rather than let it be read aloud.
                    pre.remove();
                    return;
                }
                // Blank lines around the marker keep the surrounding prose as separate blocks.
                pre.parentNode.replaceChild(document.createTextNode('\\n\\n' + marker + '\\n\\n'), pre);
            });
        }

        function cleanContent(node) {
            if (!node) return '';
            var clone = node.cloneNode(true);
            markCodeBlocks(clone);
            ['script','style','noscript','iframe','form','button','input','select','textarea','svg','figure','figcaption'].forEach(function(tag) {
                clone.querySelectorAll(tag).forEach(function(el) {
                    // Keep a wrapper that now holds a code marker (e.g. <figure><pre>…</pre></figure>),
                    // otherwise the code block would be deleted along with its container.
                    if ((el.textContent || '').indexOf(MARK_OPEN) >= 0) return;
                    el.remove();
                });
            });
            return (clone.innerText || clone.textContent || '').trim();
        }

        try {
            var clone = document.cloneNode(true);
            ['script','style','noscript','link[rel="stylesheet"]'].forEach(function(s) {
                clone.querySelectorAll(s).forEach(function(el) { el.remove(); });
            });
            stripUnlikely(clone);

            var article = clone.querySelector('article') || clone.querySelector('[role="main"]') || clone.querySelector('main');
            var best = findBestNode(clone);

            var target = null;
            if (article && best) {
                target = (textLength(article) >= textLength(best) * 0.5) ? article : best;
            } else {
                target = article || best || clone.body;
            }

            var text = cleanContent(target);

            if (text.length < 100 && clone.body) {
                text = cleanContent(clone.body);
            }

            return {
                'title': getTitle(),
                'textContent': text,
                'byline': getByline(),
                'siteName': getSiteName()
            };
        } catch(e) {
            var fallback = document.body ? document.body.innerText : '';
            return {
                'title': document.title || '',
                'textContent': fallback,
                'byline': '',
                'siteName': ''
            };
        }
    })()
    """

    private func waitForLoad(_ webView: WKWebView) async throws {
        let delegate = NavDelegate()
        webView.navigationDelegate = delegate
        objc_setAssociatedObject(webView, "navDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        try await delegate.waitForCompletion()
    }

    private func extractFromPDF(_ url: URL) async throws -> ReadingContent {
        let title = url.deletingPathExtension().lastPathComponent
        let text = try await Task.detached {
            guard let doc = PDFDocument(url: url) else { throw URLError(.cannotOpenFile) }
            var result = ""
            for i in 0..<doc.pageCount {
                if let s = doc.page(at: i)?.string { result += s + "\n\n" }
                try Task.checkCancellation()
            }
            return result
        }.value
        return ReadingContent(title: title, body: text.trimmingCharacters(in: .whitespacesAndNewlines), source: .pdf(url))
    }
}

private final class NavDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func waitForCompletion() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { self.continuation = $0 }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in self?.finish(CancellationError()) }
        }
    }

    private func finish(_ error: Error? = nil) {
        guard let c = continuation else { return }
        continuation = nil
        if let error { c.resume(throwing: error) } else { c.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }
}
