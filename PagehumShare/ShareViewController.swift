// Modified for Pagehum: save shared links using extension-safe APIs.
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let appGroupID = "group.com.test.mier.hello"
    private let sharedURLKey = "SharedURL"
    private var didHandleContent = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didHandleContent else { return }
        didHandleContent = true
        handleSharedContent()
    }

    private func handleSharedContent() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        // Prefer the URL representation even when the host also supplies a text title.
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] data, error in
                let value: String?
                if let url = data as? URL {
                    value = url.absoluteString
                } else if let bytes = data as? Data {
                    value = URL(dataRepresentation: bytes, relativeTo: nil)?.absoluteString
                } else {
                    value = data as? String
                }
                DispatchQueue.main.async {
                    self?.save(value, error: error)
                }
            }
        } else if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] data, error in
                DispatchQueue.main.async {
                    self?.save(data as? String, error: error)
                }
            }
        } else {
            showResult(title: "No web link found", message: "Share an article URL from your browser to add it to Pagehum.")
        }
    }

    private func save(_ value: String?, error: Error?) {
        guard error == nil,
              let text = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else {
            showResult(title: "Couldn’t add link", message: "Share a complete http or https article URL and try again.")
            return
        }
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil,
              let defaults = UserDefaults(suiteName: appGroupID) else {
            showResult(title: "Couldn’t save link", message: "Pagehum’s shared storage is unavailable. Open Pagehum and paste the link there.")
            return
        }
        // Do not silently replace a link that the app has not imported yet.
        if let pending = defaults.string(forKey: sharedURLKey), !pending.isEmpty, pending != url.absoluteString {
            showResult(title: "A link is waiting", message: "Open Pagehum to import your previous link, then share this article again.")
            return
        }
        defaults.set(url.absoluteString, forKey: sharedURLKey)
        showResult(title: "Link saved", message: "Open Pagehum to import this article.")
    }

    private func showResult(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        present(alert, animated: true)
    }
}
