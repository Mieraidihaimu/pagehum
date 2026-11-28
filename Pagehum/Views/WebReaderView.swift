// Modified for Pagehum: unified application and command-line naming.
import SwiftUI
import WebKit

struct WebReaderView: View {

    @ObservedObject var viewModel: ReaderModel
    let url: URL
    var showsPlaybackControls = true
    @Environment(\.colorScheme) private var colorScheme

    /// What to look for in the live page, with adjacent sentence context and playback progress
    /// so short or repeated phrases resolve accurately without matching outer article containers.
    private var highlightRequest: WebHighlightRequest? {
        viewModel.highlightRequest(at: viewModel.currentSentenceIndex)
    }

    private var appearance: ReaderAppearance {
        viewModel.currentArticleAppearance
    }

    private var effectiveColorScheme: ColorScheme {
        appearance.resolvedColorScheme(system: colorScheme)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            WebViewContainer(
                url: url,
                highlightRequest: highlightRequest,
                isPlaying: viewModel.isPlaying,
                autoScroll: viewModel.autoScroll,
                appearance: appearance,
                effectiveColorScheme: effectiveColorScheme,
                theme: WebHighlightTheme(colorScheme: effectiveColorScheme, appearance: appearance)
            )
            .id(url)
            #if os(iOS)
            .ignoresSafeArea(edges: showsPlaybackControls ? .bottom : [])
            #endif

            if showsPlaybackControls {
                PlaybackControlsView(viewModel: viewModel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle(viewModel.content?.title ?? "Reader")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.canvas, for: .navigationBar)
        #endif
        .environment(\.colorScheme, effectiveColorScheme)
    }
}

private struct WebHighlightTheme: Equatable {
    let sentenceBg: String
    let wordBg: String
    let wordText: String
    let appearance: ReaderAppearance

    init(colorScheme: ColorScheme, appearance: ReaderAppearance) {
        sentenceBg = AppTheme.webHighlightColor(for: colorScheme)
        wordBg = AppTheme.webColor(AppTheme.readerWordBg, for: colorScheme)
        wordText = AppTheme.webColor(AppTheme.readerWordText, for: colorScheme)
        self.appearance = appearance
    }

    var cssProperties: [String: String] {
        [
            "--pagehum-sentence-bg": sentenceBg,
            "--pagehum-word-bg": wordBg,
            "--pagehum-word-text": wordText,
            "--pagehum-appearance": appearance.rawValue,
        ]
    }
}

private struct WebViewContainer {
    let url: URL
    let highlightRequest: WebHighlightRequest?
    let isPlaying: Bool
    let autoScroll: Bool
    let appearance: ReaderAppearance
    let effectiveColorScheme: ColorScheme
    let theme: WebHighlightTheme

    fileprivate static func createWebView(
        url: URL,
        appearance: ReaderAppearance,
        effectiveColorScheme: ColorScheme,
        coordinator: Coordinator
    ) -> WKWebView {
        let config = WKWebViewConfiguration()
        #if os(iOS)
        config.allowsInlineMediaPlayback = true
        #endif
        let webView = WKWebView(frame: .zero, configuration: config)
        #if os(iOS)
        webView.isOpaque = false
        #endif
        applyPlatformAppearance(appearance, effectiveColorScheme: effectiveColorScheme, to: webView)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = coordinator
        webView.load(URLRequest(url: url))
        coordinator.webView = webView
        return webView
    }

    fileprivate static func applyPlatformAppearance(
        _ appearance: ReaderAppearance,
        effectiveColorScheme: ColorScheme,
        to webView: WKWebView
    ) {
        #if os(iOS)
        switch appearance {
        case .system: webView.overrideUserInterfaceStyle = .unspecified
        case .light: webView.overrideUserInterfaceStyle = .light
        case .dark: webView.overrideUserInterfaceStyle = .dark
        }
        let bgColor = UIColor(AppTheme.canvas).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: effectiveColorScheme == .dark ? .dark : .light)
        )
        webView.backgroundColor = bgColor
        webView.underPageBackgroundColor = bgColor
        #else
        switch appearance {
        case .system: webView.appearance = nil
        case .light: webView.appearance = NSAppearance(named: .aqua)
        case .dark: webView.appearance = NSAppearance(named: .darkAqua)
        }
        var bgColor = NSColor.clear
        NSAppearance(named: effectiveColorScheme == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            bgColor = NSColor(AppTheme.canvas).usingColorSpace(.sRGB) ?? .clear
        }
        webView.underPageBackgroundColor = bgColor
        #endif
    }

    fileprivate func updateWebView(_ webView: WKWebView, coordinator: Coordinator) {
        Self.applyPlatformAppearance(appearance, effectiveColorScheme: effectiveColorScheme, to: webView)
        coordinator.theme = theme
        coordinator.desiredHighlight = isPlaying ? highlightRequest : nil
        coordinator.desiredAutoScroll = autoScroll
        guard coordinator.isReady else { return }
        coordinator.applyTheme()
        coordinator.syncHighlight()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private struct HighlightState: Equatable {
            let request: WebHighlightRequest?
            let autoScroll: Bool
        }

        private struct JSHighlightPayload: Encodable {
            let text: String
            let prevText: String?
            let nextText: String?
            let progress: Double
            let blockKind: String?
            let isBlockMode: Bool
            let autoScroll: Bool
        }

        weak var webView: WKWebView?
        var isReady = false
        var theme: WebHighlightTheme
        var desiredHighlight: WebHighlightRequest?
        var desiredAutoScroll = false
        private var appliedTheme: WebHighlightTheme?
        private var appliedHighlight: HighlightState?

        init(theme: WebHighlightTheme) {
            self.theme = theme
        }

        func applyTheme() {
            guard theme != appliedTheme,
                  let data = try? JSONSerialization.data(withJSONObject: theme.cssProperties),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView?.evaluateJavaScript("window.__pagehumSetTheme(\(json));", completionHandler: nil)
            appliedTheme = theme
        }

        func syncHighlight() {
            let target = HighlightState(request: desiredHighlight, autoScroll: desiredAutoScroll)
            if let appliedHighlight {
                if appliedHighlight == target { return }
                // Avoid re-running JS if autoScroll is turned off while the same sentence stays highlighted.
                if appliedHighlight.request == target.request, !target.autoScroll, target.request != nil {
                    self.appliedHighlight = target
                    return
                }
            }

            if let request = target.request {
                let payload = JSHighlightPayload(
                    text: request.text,
                    prevText: request.prevText,
                    nextText: request.nextText,
                    progress: request.progress,
                    blockKind: request.blockKind?.rawValue,
                    isBlockMode: request.isBlockMode,
                    autoScroll: target.autoScroll
                )
                guard let data = try? JSONEncoder().encode(payload),
                      let json = String(data: data, encoding: .utf8) else { return }
                webView?.evaluateJavaScript("window.__pagehumHighlight(\(json));", completionHandler: nil)
            } else if appliedHighlight == nil || appliedHighlight?.request != nil {
                webView?.evaluateJavaScript("window.__pagehumClear();", completionHandler: nil)
            }
            appliedHighlight = target
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(WebReaderHighlightScript.source) { _, _ in
                self.isReady = true
                self.appliedTheme = nil
                self.appliedHighlight = nil
                self.applyTheme()
                self.syncHighlight()
            }
        }
    }
}

enum WebReaderHighlightScript {
    static let source = """
    (function() {
        if (window.__pagehumInstalled) return;
        window.__pagehumInstalled = true;

        var SKIP_TAGS = {
            SCRIPT: true, STYLE: true, NOSCRIPT: true, TEMPLATE: true,
            SVG: true, IFRAME: true, TEXTAREA: true, SELECT: true,
            HEAD: true, TITLE: true
        };
        var BLOCK_TAGS = {
            ADDRESS: true, ARTICLE: true, ASIDE: true, BLOCKQUOTE: true,
            DD: true, DETAILS: true, DIALOG: true, DIV: true, DL: true, DT: true,
            FIELDSET: true, FIGCAPTION: true, FIGURE: true, FOOTER: true,
            FORM: true, H1: true, H2: true, H3: true, H4: true, H5: true, H6: true,
            HEADER: true, HGROUP: true, HR: true, LI: true, MAIN: true, NAV: true,
            OL: true, P: true, PRE: true, SECTION: true, TABLE: true,
            TBODY: true, TD: true, TFOOT: true, TH: true, THEAD: true, TR: true, UL: true
        };
        var PROSE_BLOCK_SELECTOR = 'p, li, blockquote, h1, h2, h3, h4, h5, h6, td, th, figcaption, dt, dd, pre';

        var textIndex = null;
        var lastCursor = 0;
        var lastProgress = 0;
        var activeBlockEl = null;
        var currentSentenceBg = '';
        var observer = null;

        function ensureHighlightStyle(bgColor) {
            var style = document.getElementById('pagehum-highlight-style');
            if (!style) {
                style = document.createElement('style');
                style.id = 'pagehum-highlight-style';
                var target = document.head || document.documentElement;
                if (target) target.appendChild(style);
            }
            var color = bgColor || currentSentenceBg || 'var(--pagehum-sentence-bg, rgba(14, 165, 233, 0.14))';
            style.textContent =
                '::highlight(pagehum-current) { background-color: ' + color + '; }\\n' +
                '.pagehum-active-block { background-color: ' + color + ' !important; border-radius: 4px; transition: background-color 0.25s ease; }';
        }

        function parseBackground(el) {
            if (!el) return null;
            var bg = window.getComputedStyle(el).backgroundColor;
            if (!bg) return null;
            var match = bg.match(/rgba?\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)(?:\\s*,\\s*([\\d.]+))?\\s*\\)/);
            if (!match) return null;
            var alpha = match[4] !== undefined ? parseFloat(match[4]) : 1;
            if (alpha <= 0.1) return null;
            var r = parseInt(match[1], 10) / 255;
            var g = parseInt(match[2], 10) / 255;
            var b = parseInt(match[3], 10) / 255;
            return 0.2126 * r + 0.7152 * g + 0.0722 * b;
        }

        function updateAppearanceOverride(mode) {
            var existing = document.getElementById('pagehum-appearance-override');
            if (existing) existing.remove();
            if (!mode || mode === 'system') return;

            var bodyLum = parseBackground(document.body);
            var htmlLum = parseBackground(document.documentElement);
            var effectiveLum = bodyLum !== null ? bodyLum : htmlLum;

            var css = null;
            if (mode === 'dark') {
                if (effectiveLum === null || effectiveLum >= 0.3) {
                    var bgRule = effectiveLum === null ? 'background-color: #ffffff !important;' : '';
                    css = 'html { ' + bgRule + ' filter: invert(0.92) hue-rotate(180deg) !important; } ' +
                          'img, video, picture, canvas, svg { filter: invert(1) hue-rotate(180deg) !important; }';
                }
            } else if (mode === 'light') {
                if (effectiveLum !== null && effectiveLum < 0.25) {
                    css = 'html { filter: invert(0.92) hue-rotate(180deg) !important; } ' +
                          'img, video, picture, canvas, svg { filter: invert(1) hue-rotate(180deg) !important; }';
                }
            }

            if (css && document.head) {
                var style = document.createElement('style');
                style.id = 'pagehum-appearance-override';
                style.textContent = css;
                document.head.appendChild(style);
            }
        }

        window.__pagehumSetTheme = function(tokens) {
            if (!tokens || typeof tokens !== 'object') return;
            var root = document.documentElement;
            if (root) {
                for (var key in tokens) {
                    if (Object.prototype.hasOwnProperty.call(tokens, key)) {
                        root.style.setProperty(key, tokens[key]);
                    }
                }
            }
            if (tokens['--pagehum-sentence-bg']) {
                currentSentenceBg = tokens['--pagehum-sentence-bg'];
            }
            ensureHighlightStyle(currentSentenceBg);
            updateAppearanceOverride(tokens['--pagehum-appearance']);
        };

        function normalizePiece(ch) {
            if (/\\s/.test(ch)) return ' ';
            if (ch === '\\u00AD' || ch === '\\u200B' || ch === '\\u200C' || ch === '\\u200D' || ch === '\\uFEFF') return '';
            if (ch === '\\u2018' || ch === '\\u2019' || ch === '\\u2032' || ch === '\\u02BC') return "'";
            if (ch === '\\u201C' || ch === '\\u201D' || ch === '\\u2033' || ch === '\\u00AB' || ch === '\\u00BB') return '"';
            if (ch === '\\u2010' || ch === '\\u2011' || ch === '\\u2012' || ch === '\\u2013' || ch === '\\u2014' || ch === '\\u2015' || ch === '\\u2212') return '-';
            if (ch === '\\u2026') return '...';
            return ch.toLowerCase();
        }

        function normalizeString(str) {
            if (!str) return '';
            var out = [];
            var prevSpace = true;
            for (var i = 0; i < str.length; i++) {
                var piece = normalizePiece(str.charAt(i));
                for (var j = 0; j < piece.length; j++) {
                    var c = piece.charAt(j);
                    if (c === ' ') {
                        if (!prevSpace) {
                            out.push(' ');
                            prevSpace = true;
                        }
                    } else {
                        out.push(c);
                        prevSpace = false;
                    }
                }
            }
            if (out.length > 0 && out[out.length - 1] === ' ') out.pop();
            return out.join('');
        }

        function isVisibleElement(el) {
            if (!el || el.nodeType !== 1) return false;
            if (el.hidden || el.getAttribute('aria-hidden') === 'true') return false;
            var style = window.getComputedStyle(el);
            if (!style) return true;
            if (style.display === 'none' || style.visibility === 'hidden') return false;
            if (parseFloat(style.opacity) === 0) return false;
            if (style.overflow === 'hidden' && (style.width === '1px' || style.height === '1px')) {
                return false;
            }
            if (window.innerWidth > 0 && window.innerHeight > 0 && style.display !== 'contents') {
                if (el.getClientRects().length === 0) return false;
            }
            return true;
        }

        function chooseRoot() {
            var body = document.body;
            if (!body) return null;
            var bodyLen = (body.textContent || '').trim().length;
            if (bodyLen === 0) return body;

            var groups = ['article', 'main, [role="main"]'];
            for (var g = 0; g < groups.length; g++) {
                var candidates = document.querySelectorAll(groups[g]);
                var best = null;
                var bestLen = 0;
                for (var i = 0; i < candidates.length; i++) {
                    var el = candidates[i];
                    if (!isVisibleElement(el)) continue;
                    var len = (el.textContent || '').trim().length;
                    if (len > bestLen) {
                        bestLen = len;
                        best = el;
                    }
                }
                if (best && bestLen >= Math.min(100, bodyLen) && bestLen >= bodyLen * 0.25) {
                    return best;
                }
            }
            return body;
        }

        function closestBlockElement(node) {
            var el = node && node.nodeType === 3 ? node.parentElement : node;
            while (el && el !== document.body && el !== document.documentElement) {
                if (BLOCK_TAGS[el.tagName]) return el;
                el = el.parentElement;
            }
            return el || document.body;
        }

        function attachObserver() {
            if (observer || !document.body || typeof MutationObserver === 'undefined') return;
            observer = new MutationObserver(function(mutations) {
                for (var i = 0; i < mutations.length; i++) {
                    var t = mutations[i].target;
                    if (t && (t.id === 'pagehum-highlight-style' || t.id === 'pagehum-appearance-override')) continue;
                    textIndex = null;
                    break;
                }
            });
            observer.observe(document.body, { childList: true, subtree: true });
        }

        function buildTextIndex(includeAllBody) {
            var root = includeAllBody ? document.body : chooseRoot();
            if (!root) {
                textIndex = { normText: '', map: [], isFallbackBody: !!includeAllBody };
                return;
            }
            attachObserver();

            var walker = document.createTreeWalker(
                root,
                NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
                {
                    acceptNode: function(node) {
                        if (node.nodeType === 1) {
                            var tag = node.tagName;
                            if (SKIP_TAGS[tag] || (!includeAllBody && (tag === 'NAV' || tag === 'ASIDE' || tag === 'FOOTER'))) {
                                return NodeFilter.FILTER_REJECT;
                            }
                            if (!isVisibleElement(node)) {
                                return NodeFilter.FILTER_REJECT;
                            }
                            if (tag === 'BR') {
                                return NodeFilter.FILTER_ACCEPT;
                            }
                            return NodeFilter.FILTER_SKIP;
                        }
                        return NodeFilter.FILTER_ACCEPT;
                    }
                },
                false
            );

            var chars = [];
            var map = [];
            var prevSpace = true;
            var lastBlock = null;
            var pendingSpace = false;
            var currentNode;

            while ((currentNode = walker.nextNode())) {
                if (currentNode.nodeType === 1 && currentNode.tagName === 'BR') {
                    if (!prevSpace) {
                        pendingSpace = true;
                    }
                    continue;
                }

                var val = currentNode.nodeValue;
                if (!val) continue;

                var block = closestBlockElement(currentNode);
                if ((pendingSpace || (lastBlock && block !== lastBlock)) && !prevSpace) {
                    chars.push(' ');
                    map.push({ node: currentNode, offset: 0, virtual: true });
                    prevSpace = true;
                }
                pendingSpace = false;
                lastBlock = block;

                for (var i = 0; i < val.length; i++) {
                    var piece = normalizePiece(val.charAt(i));
                    for (var j = 0; j < piece.length; j++) {
                        var c = piece.charAt(j);
                        if (c === ' ') {
                            if (!prevSpace) {
                                chars.push(' ');
                                map.push({ node: currentNode, offset: i });
                                prevSpace = true;
                            }
                        } else {
                            chars.push(c);
                            map.push({ node: currentNode, offset: i });
                            prevSpace = false;
                        }
                    }
                }
            }

            textIndex = {
                normText: chars.join(''),
                map: map,
                isFallbackBody: !!includeAllBody
            };
        }

        function matchesBlockKind(pos, map, blockKind) {
            var entry = map[pos];
            if (!entry || !entry.node) return false;
            var el = entry.node.nodeType === 3 ? entry.node.parentElement : entry.node;
            if (!el) return false;
            if (blockKind === 'code') return !!el.closest('pre');
            if (blockKind === 'table') return !!el.closest('table');
            return true;
        }

        function searchNearCursor(haystack, map, needle, req) {
            if (!needle) return -1;
            var matches = [];
            var pos = 0;
            while ((pos = haystack.indexOf(needle, pos)) !== -1) {
                matches.push(pos);
                if (matches.length >= 200) break;
                pos += 1;
            }
            if (matches.length === 0) return -1;

            var candidates = matches;
            if (req.blockKind) {
                var preferred = matches.filter(function(idx) {
                    return matchesBlockKind(idx, map, req.blockKind);
                });
                if (preferred.length > 0) {
                    candidates = preferred;
                }
            }
            if (candidates.length === 1) return candidates[0];

            var progress = typeof req.progress === 'number' ? req.progress : 0;
            var progressJump = Math.abs(progress - lastProgress);
            if (lastCursor > 0 && progressJump <= 0.15) {
                var windowStart = Math.max(0, lastCursor - 200);
                for (var i = 0; i < candidates.length; i++) {
                    var c = candidates[i];
                    if (c >= windowStart && (c - lastCursor) < 8000) {
                        return c;
                    }
                }
            }

            var targetOffset = Math.floor(haystack.length * progress);
            var bestIdx = candidates[0];
            var bestDist = Infinity;
            for (var j = 0; j < candidates.length; j++) {
                var dist = Math.abs(candidates[j] - targetOffset);
                if (dist < bestDist) {
                    bestDist = dist;
                    bestIdx = candidates[j];
                }
            }
            return bestIdx;
        }

        function mapToRange(map, startIdx, endIdx) {
            while (startIdx < endIdx && map[startIdx] && map[startIdx].virtual) {
                startIdx++;
            }
            while (endIdx > startIdx && map[endIdx] && map[endIdx].virtual) {
                endIdx--;
            }
            var startPos = map[startIdx];
            var endPos = map[endIdx];
            if (!startPos || !endPos || !startPos.node || !endPos.node) return null;

            var range = document.createRange();
            range.setStart(startPos.node, Math.min(startPos.offset, startPos.node.nodeValue.length));
            range.setEnd(endPos.node, Math.min(endPos.offset + 1, endPos.node.nodeValue.length));
            return range;
        }

        function findInIndex(req) {
            var normText = textIndex.normText;
            var map = textIndex.map;
            var needle = normalizeString(req.text);
            if (!needle) return null;

            var matchStart = -1;
            var matchLen = needle.length;

            if (needle.length < 20 && (req.prevText || req.nextText)) {
                var prev = normalizeString(req.prevText || '').slice(-35);
                var next = normalizeString(req.nextText || '').slice(0, 35);
                var attempts = [];
                if (prev && next) attempts.push({ text: prev + ' ' + needle + ' ' + next, offset: prev.length + 1 });
                if (prev) attempts.push({ text: prev + ' ' + needle, offset: prev.length + 1 });
                if (next) attempts.push({ text: needle + ' ' + next, offset: 0 });
                for (var a = 0; a < attempts.length; a++) {
                    var compIdx = searchNearCursor(normText, map, attempts[a].text, req);
                    if (compIdx >= 0) {
                        matchStart = compIdx + attempts[a].offset;
                        break;
                    }
                }
            }

            if (matchStart < 0) {
                matchStart = searchNearCursor(normText, map, needle, req);
            }

            if (matchStart < 0 && needle.length > 60) {
                var shortNeedle = needle.slice(0, 60);
                matchStart = searchNearCursor(normText, map, shortNeedle, req);
                if (matchStart >= 0) {
                    matchLen = shortNeedle.length;
                    if (needle.length > 85) {
                        var suffix = needle.slice(-25);
                        var searchFrom = matchStart + 40;
                        var searchEnd = Math.min(normText.length, matchStart + needle.length + 60);
                        var suffixIdx = normText.indexOf(suffix, searchFrom);
                        if (suffixIdx >= 0 && suffixIdx + suffix.length <= searchEnd) {
                            matchLen = (suffixIdx + suffix.length) - matchStart;
                        }
                    }
                }
            }

            if (matchStart < 0 && needle.length >= 40) {
                var tailNeedle = needle.slice(-Math.min(needle.length, 50));
                matchStart = searchNearCursor(normText, map, tailNeedle, req);
                if (matchStart >= 0) {
                    matchLen = tailNeedle.length;
                }
            }

            if (matchStart < 0) return null;

            lastCursor = matchStart + matchLen;
            lastProgress = typeof req.progress === 'number' ? req.progress : lastProgress;
            return mapToRange(map, matchStart, Math.min(matchStart + matchLen - 1, map.length - 1));
        }

        function findMatchRange(req) {
            if (!textIndex) buildTextIndex(false);
            var range = findInIndex(req);
            if (!range && !textIndex.isFallbackBody) {
                buildTextIndex(true);
                range = findInIndex(req);
            }
            return range;
        }

        function findInnermostBlock(node, blockKind) {
            var el = node && node.nodeType === 3 ? node.parentElement : node;
            if (!el) return null;
            if (blockKind === 'code') {
                return el.closest('pre') || el.closest('code') || el;
            }
            if (blockKind === 'table') {
                return el.closest('table') || el;
            }
            var semantic = el.closest(PROSE_BLOCK_SELECTOR);
            if (semantic) return semantic;

            var cur = el;
            while (cur && cur !== document.body && cur !== document.documentElement) {
                var tag = cur.tagName;
                if (tag === 'ARTICLE' || tag === 'MAIN' || tag === 'SECTION') {
                    return el;
                }
                var display = window.getComputedStyle(cur).display;
                if (display && display.indexOf('inline') !== 0) {
                    return cur;
                }
                cur = cur.parentElement;
            }
            return el;
        }

        function clearHighlight() {
            if (typeof CSS !== 'undefined' && CSS.highlights) {
                CSS.highlights.delete('pagehum-current');
            }
            if (activeBlockEl) {
                activeBlockEl.classList.remove('pagehum-active-block');
                activeBlockEl = null;
            }
        }

        window.__pagehumClear = clearHighlight;

        window.__pagehumHighlight = function(input, legacyAutoScroll) {
            var req = typeof input === 'string'
                ? { text: input, autoScroll: !!legacyAutoScroll, progress: 0, isBlockMode: false }
                : (input || {});

            ensureHighlightStyle(currentSentenceBg);
            clearHighlight();
            var range = findMatchRange(req);
            if (!range) return false;

            var supportsCustomHighlights = typeof CSS !== 'undefined' && CSS.highlights && typeof Highlight !== 'undefined';
            var useCustomHighlight = !req.isBlockMode && supportsCustomHighlights;

            if (useCustomHighlight) {
                CSS.highlights.set('pagehum-current', new Highlight(range));
            } else {
                activeBlockEl = findInnermostBlock(range.startContainer, req.blockKind);
                if (activeBlockEl) {
                    activeBlockEl.classList.add('pagehum-active-block');
                }
            }

            if (req.autoScroll) {
                var rect = (activeBlockEl || range).getBoundingClientRect();
                if (rect && rect.height > 0 && (rect.top < 80 || rect.bottom > window.innerHeight - 100)) {
                    var docEl = document.documentElement;
                    if (docEl && docEl.scrollHeight > window.innerHeight + 10) {
                        var targetY = window.scrollY + rect.top - (window.innerHeight * 0.35);
                        window.scrollTo({ top: Math.max(0, targetY), behavior: 'smooth' });
                    } else {
                        var scrollEl = activeBlockEl || (range.startContainer.nodeType === 3 ? range.startContainer.parentElement : range.startContainer);
                        if (scrollEl && scrollEl.scrollIntoView) {
                            scrollEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
                        }
                    }
                }
            }
            return true;
        };
    })();
    """
}

#if os(iOS)
extension WebViewContainer: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(theme: theme) }

    func makeUIView(context: Context) -> WKWebView {
        Self.createWebView(
            url: url,
            appearance: appearance,
            effectiveColorScheme: effectiveColorScheme,
            coordinator: context.coordinator
        )
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, coordinator: context.coordinator)
    }
}
#else
extension WebViewContainer: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(theme: theme) }

    func makeNSView(context: Context) -> WKWebView {
        Self.createWebView(
            url: url,
            appearance: appearance,
            effectiveColorScheme: effectiveColorScheme,
            coordinator: context.coordinator
        )
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, coordinator: context.coordinator)
    }
}
#endif
