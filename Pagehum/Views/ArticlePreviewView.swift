import SwiftUI
import WebKit

/// A browsing preview that leaves the current reader and playback session intact.
struct ArticlePreviewView<Actions: View>: View {
    let title: String
    let url: URL
    @ViewBuilder var actions: Actions
    @Environment(\.dismiss) private var dismiss
    @State private var showsOriginal = false
    @State private var readerUnavailable = false
    @State private var readerDocument: ReaderDocument?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var reloadID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline).lineLimit(3)
                    Link(destination: url) {
                        Label(url.host() ?? url.absoluteString, systemImage: "arrow.up.right.square")
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .tint(AppTheme.accentText)
                    .help("Open in browser")
                    Button {
                        showPage(original: !showsOriginal)
                    } label: {
                        Label(showsOriginal ? "Reader view" : "Original page",
                              systemImage: showsOriginal ? "doc.plaintext" : "globe")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(AppTheme.accentText)
                    }
                    .buttonStyle(.plain)
                    if readerUnavailable {
                        Text("Reader view unavailable")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()
            ZStack(alignment: .top) {
                if showsOriginal || readerDocument != nil {
                    PreviewWebView(url: url, document: showsOriginal ? nil : readerDocument,
                                   isLoading: $isLoading, loadError: $loadError)
                        .id(reloadID)
                        .opacity(loadError == nil ? 1 : 0)
                        .allowsHitTesting(loadError == nil)
                        .accessibilityHidden(loadError != nil)
                }
                if let loadError {
                    ContentUnavailableView {
                        Label("Couldn’t load preview", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Try again") {
                            self.loadError = nil
                            isLoading = true
                            reloadID = UUID()
                        }
                        Link("Open in browser", destination: url)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading preview…").font(.callout)
                    }
                    .padding(12)
                    .background(AppTheme.elevated, in: Capsule())
                    .overlay(Capsule().strokeBorder(AppTheme.borderSubtle))
                    .padding(.top, 16)
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            actions
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(16)
        }
        .appTheme()
        .task(id: showsOriginal) { await loadReader() }
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 800, minHeight: 480, idealHeight: 680)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func showPage(original: Bool) {
        showsOriginal = original
        isLoading = true
        loadError = nil
        reloadID = UUID()
    }

    private func loadReader() async {
        guard !showsOriginal, readerDocument == nil else { return }
        readerUnavailable = false
        do {
            let document = try await ReaderWebDocumentExtractor().extract(url: url)
            try Task.checkCancellation()
            readerDocument = document
        } catch {
            guard !Task.isCancelled else { return }
            readerUnavailable = true
            showPage(original: true)
        }
    }
}

enum ArticlePreviewPage {
    static func html(for document: ReaderDocument) -> String {
        let language = (document.manifest.language ?? "")
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        let direction = document.manifest.direction == "rtl" ? "rtl" : "auto"
        return """
        <!doctype html>
        <html lang="\(language)" dir="\(direction)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="referrer" content="no-referrer">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src https: http: data:">
          <style>
            :root {
              color-scheme: light dark;
              \(palette(for: .light))
            }
            @media (prefers-color-scheme: dark) {
              :root { \(palette(for: .dark)) }
            }
            html {
              background: var(--canvas);
              color: var(--text);
            }
            body {
              box-sizing: border-box;
              max-width: 72ch;
              margin: 0 auto;
              padding: clamp(16px, 4vw, 36px);
              font: 1.125rem / 1.6 system-ui, sans-serif;
              overflow-wrap: anywhere;
            }
            h1, h2, h3, h4, h5, h6 { line-height: 1.25; }
            a { color: var(--link); text-decoration: underline; }
            img { max-width: 100%; height: auto; }
            figure { margin-inline: 0; }
            figcaption, caption { color: var(--secondary); font-size: .9em; }
            blockquote { margin-inline: 0; padding-inline-start: 1em; border-inline-start: 3px solid var(--link); }
            pre, code, kbd, samp, mark, th { background: var(--elevated); color: var(--text); }
            pre { padding: 1em; overflow-x: auto; border-radius: 8px; font-size: .9em; }
            code, kbd, samp { border-radius: 4px; padding: .1em .25em; }
            pre code { background: transparent; padding: 0; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid var(--secondary); padding: .4em .6em; }
          </style>
        </head>
        <body>\(document.articleHTML)</body>
        </html>
        """
    }

    private static func palette(for scheme: ColorScheme) -> String {
        """
        --canvas: \(AppTheme.webColor(AppTheme.canvas, for: scheme));
        --text: \(AppTheme.webColor(AppTheme.textPrimary, for: scheme));
        --secondary: \(AppTheme.webColor(AppTheme.textSecondary, for: scheme));
        --link: \(AppTheme.webColor(AppTheme.accentText, for: scheme));
        --elevated: \(AppTheme.webColor(AppTheme.elevated, for: scheme));
        """
    }
}

private struct PreviewWebView {
    let url: URL
    let document: ReaderDocument?
    @Binding var isLoading: Bool
    @Binding var loadError: String?
    @Environment(\.openURL) private var openURL

    init(url: URL, document: ReaderDocument?, isLoading: Binding<Bool>, loadError: Binding<String?>) {
        self.url = url
        self.document = document
        _isLoading = isLoading
        _loadError = loadError
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    private func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if document != nil {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            configuration.websiteDataStore = .nonPersistent()
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        if let document {
            #if os(iOS)
            webView.isOpaque = false
            webView.backgroundColor = UIColor(AppTheme.canvas)
            webView.underPageBackgroundColor = UIColor(AppTheme.canvas)
            #else
            webView.allowsMagnification = true
            webView.underPageBackgroundColor = NSColor(AppTheme.canvas)
            #endif
            webView.loadHTMLString(ArticlePreviewPage.html(for: document), baseURL: nil)
        } else {
            webView.allowsBackForwardNavigationGestures = true
            webView.load(URLRequest(url: url, timeoutInterval: 30))
        }
        return webView
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: PreviewWebView

        init(parent: PreviewWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard parent.document != nil, navigationAction.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            if let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme) {
                parent.openURL(url)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.loadError = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            parent.isLoading = false
            parent.loadError = "The preview stopped responding. Try loading it again."
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            failed(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failed(error)
        }

        private func failed(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            parent.isLoading = false
            parent.loadError = error.localizedDescription
        }
    }
}

#if os(iOS)
extension PreviewWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.navigationDelegate = nil
        uiView.stopLoading()
    }
}
#else
extension PreviewWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.navigationDelegate = nil
        nsView.stopLoading()
    }
}
#endif
