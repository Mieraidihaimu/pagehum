import SwiftUI
import WebKit

/// A browsing preview that leaves the current reader and playback session intact.
struct ArticlePreviewView<Actions: View>: View {
    let title: String
    let url: URL
    @ViewBuilder var actions: Actions
    @Environment(\.dismiss) private var dismiss
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
                    }
                    .help("Open in browser")
                }
                Spacer(minLength: 0)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()
            ZStack(alignment: .top) {
                PreviewWebView(url: url, isLoading: $isLoading, loadError: $loadError)
                    .id(reloadID)
                    .opacity(loadError == nil ? 1 : 0)
                    .allowsHitTesting(loadError == nil)
                    .accessibilityHidden(loadError != nil)
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
                    .frame(maxHeight: .infinity)
                } else if isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading preview…").font(.callout)
                    }
                    .padding(12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 16)
                    .accessibilityElement(children: .combine)
                }
            }
            Divider()
            actions
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(16)
        }
        .background(Color.platformGroupedBackground)
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 800, minHeight: 480, idealHeight: 680)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

private struct PreviewWebView {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    private func makeWebView(coordinator: Coordinator) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url, timeoutInterval: 30))
        return webView
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: PreviewWebView

        init(parent: PreviewWebView) { self.parent = parent }

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
}
#else
extension PreviewWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
