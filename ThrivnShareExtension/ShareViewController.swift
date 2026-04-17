import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Entry point for the Share Extension. Extracts shared content from the
/// extension context and presents the SwiftUI ShareView in a hosting controller.
@objc(ShareViewController)
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments, !attachments.isEmpty else {
            close()
            return
        }

        extractSharedContent(from: attachments) { [weak self] text, url in
            DispatchQueue.main.async {
                self?.presentShareView(text: text, url: url)
            }
        }
    }

    // MARK: - Content Extraction

    private func extractSharedContent(
        from attachments: [NSItemProvider],
        completion: @escaping (String?, URL?) -> Void
    ) {
        var extractedText: String?
        var extractedURL: URL?
        let group = DispatchGroup()

        for provider in attachments {
            // URL
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                    if let url = item as? URL {
                        extractedURL = url
                    } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        extractedURL = url
                    }
                    group.leave()
                }
            }

            // Plain text
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                    if let text = item as? String {
                        extractedText = text
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            completion(extractedText, extractedURL)
        }
    }

    // MARK: - UI

    private func presentShareView(text: String?, url: URL?) {
        let shareView = ShareView(
            sharedText: text,
            sharedURL: url,
            onSave: { [weak self] in self?.close() },
            onCancel: { [weak self] in self?.close() }
        )

        let hostingController = UIHostingController(rootView: shareView)
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
