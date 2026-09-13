// Modified for Pagehum: unified application and command-line naming.
import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let appGroupID = "group.com.test.mier.hello"
    private let sharedURLKey = "SharedURL"

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleSharedContent()
    }

    private func handleSharedContent() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            close()
            return
        }

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] data, _ in
                        DispatchQueue.main.async {
                            if let url = data as? URL {
                                self?.saveAndOpenApp(url: url.absoluteString)
                            } else if let urlData = data as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                                self?.saveAndOpenApp(url: url.absoluteString)
                            } else {
                                self?.close()
                            }
                        }
                    }
                    return
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] data, _ in
                        DispatchQueue.main.async {
                            if let text = data as? String, text.hasPrefix("http") {
                                self?.saveAndOpenApp(url: text)
                            } else {
                                self?.close()
                            }
                        }
                    }
                    return
                }
            }
        }
        close()
    }

    private func saveAndOpenApp(url: String) {
        let defaults = UserDefaults(suiteName: appGroupID)
        defaults?.set(url, forKey: sharedURLKey)
        defaults?.synchronize()

        let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        if let appURL = URL(string: "pagehum://open?url=\(encoded)") {
            openURL(appURL)
        }

        close()
    }

    private func openURL(_ url: URL) {
        var responder: UIResponder? = self
        while let r = responder {
            if r.responds(to: NSSelectorFromString("openURL:")) {
                r.perform(NSSelectorFromString("openURL:"), with: url)
                return
            }
            responder = r.next
        }
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
