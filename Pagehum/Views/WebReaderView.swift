// Modified for Pagehum: unified application and command-line naming.
import SwiftUI
import WebKit

struct WebReaderView: View {

    @ObservedObject var viewModel: ReaderModel
    let url: URL
    var showsPlaybackControls = true
    @Environment(\.colorScheme) private var colorScheme

    /// What to look for in the live page. For a code block this is a line of the source rather than
    /// the spoken announcement, so the page's own `<pre>` gets highlighted.
    private var currentSentence: String? {
        viewModel.highlightNeedle(at: viewModel.currentSentenceIndex)
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
                currentSentence: currentSentence,
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
    let currentSentence: String?
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
        guard coordinator.isReady else { return }
        coordinator.applyTheme()
        if isPlaying, let sentence = currentSentence {
            highlightSentence(sentence, autoScroll: autoScroll, in: webView)
        } else if !isPlaying {
            clearHighlight(in: webView)
        }
    }

    private func highlightSentence(_ sentence: String, autoScroll: Bool, in webView: WKWebView) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: [sentence]),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        let inner = String(jsonString.dropFirst(1).dropLast(1))
        let js = "window.__pagehumHighlight(\(inner), \(autoScroll ? "true" : "false"));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func clearHighlight(in webView: WKWebView) {
        webView.evaluateJavaScript("window.__pagehumClear();", completionHandler: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var isReady = false
        var theme: WebHighlightTheme
        private var appliedTheme: WebHighlightTheme?

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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(Self.highlightJS) { _, _ in
                self.isReady = true
                self.appliedTheme = nil
                self.applyTheme()
            }
        }

        static let highlightJS = """
        (function() {
            var currentMark = null;
            var lastAutoScroll = false;

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
                updateAppearanceOverride(tokens['--pagehum-appearance']);
                if (currentMark) {
                    currentMark.style.backgroundColor = 'var(--pagehum-sentence-bg)';
                }
            };

            function escapeRegex(s) {
                return s.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
            }

            function findTextInBody(searchText) {
                if (!searchText || searchText.length < 10) return null;

                // Normalize whitespace for comparison
                var needle = searchText.replace(/\\s+/g, ' ').trim();
                // Try first 60 chars to avoid long-sentence mismatches
                var shortNeedle = needle.substring(0, 60);

                var walker = document.createTreeWalker(
                    document.body,
                    NodeFilter.SHOW_TEXT,
                    null,
                    false
                );

                var node;
                while (node = walker.nextNode()) {
                    var text = node.textContent;
                    if (text.replace(/\\s+/g, ' ').indexOf(shortNeedle) >= 0) {
                        return node.parentElement;
                    }
                }

                // Fallback: search in element innerText
                var all = document.body.querySelectorAll('p, li, td, h1, h2, h3, h4, h5, h6, span, div, blockquote');
                for (var i = 0; i < all.length; i++) {
                    var el = all[i];
                    var inner = (el.innerText || '').replace(/\\s+/g, ' ');
                    if (inner.indexOf(shortNeedle) >= 0) {
                        return el;
                    }
                }
                return null;
            }

            window.__pagehumHighlight = function(sentence, autoScroll) {
                var previousMark = currentMark;
                // Clear previous
                if (currentMark) {
                    currentMark.style.removeProperty('background-color');
                    currentMark.style.removeProperty('border-radius');
                    currentMark.style.removeProperty('transition');
                    currentMark = null;
                }

                var el = findTextInBody(sentence);
                if (el) {
                    currentMark = el;
                    el.style.backgroundColor = 'var(--pagehum-sentence-bg)';
                    el.style.borderRadius = '4px';
                    el.style.transition = 'background-color 0.3s ease';

                    if (autoScroll && (el !== previousMark || !lastAutoScroll)) {
                        var rect = el.getBoundingClientRect();
                        if (rect.top < 80 || rect.bottom > window.innerHeight - 100) {
                            el.scrollIntoView({ behavior: 'smooth', block: 'center' });
                        }
                    }
                }
                lastAutoScroll = !!autoScroll;
            };

            window.__pagehumClear = function() {
                if (currentMark) {
                    currentMark.style.removeProperty('background-color');
                    currentMark.style.removeProperty('border-radius');
                    currentMark.style.removeProperty('transition');
                    currentMark = null;
                }
            };
        })();
        """
    }
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
