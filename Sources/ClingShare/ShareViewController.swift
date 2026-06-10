/**
 Share extension principal class: hosts the SwiftUI compose view and extracts
 the shared text / URL / image from the extension context.

 Platform rule this design lives under: a share extension can NEVER start a
 Live Activity (`Activity.request` is app/intent/push only). So the flow here
 is save a *pending* pin to the shared store, post the Darwin notification,
 schedule an immediate "tap to pin it" local notification, and hand off — the
 app activates pending pins the moment it next runs. The compose UI says this
 out loud rather than pretending.
 */
import UIKit
import SwiftUI
import UniformTypeIdentifiers

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let compose = ShareComposeView(
            extractor: { [weak self] in await self?.extractShared() ?? SharedContent() },
            onDone: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            })

        let host = UIHostingController(rootView: compose)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    /// Pull the first text, URL, and image out of whatever was shared.
    private func extractShared() async -> SharedContent {
        var content = SharedContent()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap(\.attachments)
            .flatMap { $0 } ?? []

        for provider in providers {
            if content.url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
                   !url.isFileURL {
                    content.url = url
                    continue
                }
            }
            if content.text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    content.text = text
                    continue
                }
            }
            if content.imageData == nil, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                content.imageData = await loadImageData(from: provider)
            }
        }
        return content
    }

    private func loadImageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

/// What arrived through the share sheet.
struct SharedContent: Sendable {
    var text: String?
    var url: URL?
    var imageData: Data?
}
