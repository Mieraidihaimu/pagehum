// Modified for Pagehum: unified application and command-line naming.
import SwiftUI
import WebKit

struct WebReaderView: View {

    @ObservedObject var viewModel: ReaderModel
    let url: URL
    var showsPlaybackControls = true

    /// What to look for in the live page. For a code block this is a line of the source rather than
    /// the spoken announcement, so the page's own `<pre>` gets highlighted.
    private var currentSentence: String? {
        viewModel.highlightNeedle(at: viewModel.currentSentenceIndex)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            WebViewContainer(
                url: url,
                currentSentence: currentSentence,
                isPlaying: viewModel.isPlaying
            )
            .id(url)
            #if os(iOS)
            .ignoresSafeArea(edges: .bottom)
            #endif

            if showsPlaybackControls {
                PlaybackControlsView(viewModel: viewModel)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
                .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
            }
        }
        .navigationTitle(viewModel.content?.title ?? "Reader")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        #endif
    }
}

private struct WebViewContainer {
    let url: URL
    let currentSentence: String?
    let isPlaying: Bool

    fileprivate static func createWebView(url: URL, coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        #if os(iOS)
        config.allowsInlineMediaPlayback = true
        #endif
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = coordinator
        webView.load(URLRequest(url: url))
        coordinator.webView = webView
        return webView
    }

    fileprivate func updateWebView(_ webView: WKWebView, coordinator: Coordinator) {
        guard coordinator.isReady else { return }
        if isPlaying, let sentence = currentSentence {
            highlightSentence(sentence, in: webView)
        } else if !isPlaying {
            clearHighlight(in: webView)
        }
    }

    private func highlightSentence(_ sentence: String, in webView: WKWebView) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: [sentence]),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        let inner = String(jsonString.dropFirst(1).dropLast(1))
        let js = "window.__pagehumHighlight(\(inner));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func clearHighlight(in webView: WKWebView) {
        webView.evaluateJavaScript("window.__pagehumClear();", completionHandler: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var isReady = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(Self.highlightJS) { _, _ in
                self.isReady = true
            }
        }

        static let highlightJS = """
        (function() {
            var currentMark = null;

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

            window.__pagehumHighlight = function(sentence) {
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
                    el.style.backgroundColor = 'rgba(0, 122, 255, 0.12)';
                    el.style.borderRadius = '4px';
                    el.style.transition = 'background-color 0.3s ease';
                }
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
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        Self.createWebView(url: url, coordinator: context.coordinator)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, coordinator: context.coordinator)
    }
}
#else
extension WebViewContainer: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        Self.createWebView(url: url, coordinator: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, coordinator: context.coordinator)
    }
}
#endif
