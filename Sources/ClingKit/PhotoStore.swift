/**
 `PhotoStore`: pin photos as files in the App Group container. Payloads carry
 only the *filename* — the activity ContentState has a ~4KB budget, and the
 widget process shares the container, so it loads the bytes itself.
 */
import Foundation
#if canImport(UIKit)
import UIKit
#endif

public final class PhotoStore: @unchecked Sendable {
    public static let shared = PhotoStore()

    private let appGroupID: String

    public init(appGroupID: String = ClingKit.appGroupID) {
        self.appGroupID = appGroupID
    }

    /// `…/<AppGroup>/cling-photos/`, created on demand. Falls back to Caches
    /// when the App Group is unavailable (unprovisioned dev build) — photos
    /// then don't reach the widget, but nothing crashes.
    private var directoryURL: URL? {
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let dir = base?.appendingPathComponent("cling-photos", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func url(for filename: String) -> URL? {
        directoryURL?.appendingPathComponent(filename)
    }

    /// Persist already-encoded image data. Returns the filename to store in
    /// the payload.
    public func save(_ data: Data, fileExtension: String = "jpg") -> String? {
        let filename = "\(UUID().uuidString).\(fileExtension)"
        guard let url = url(for: filename),
              (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return filename
    }

    #if canImport(UIKit)
    /// Downscale + JPEG-encode + persist. 600px is plenty for a lock-screen
    /// thumbnail and keeps the shared container lean.
    public func save(_ image: UIImage, maxDimension: CGFloat = 600) -> String? {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = scaled.jpegData(compressionQuality: 0.8) else { return nil }
        return save(data)
    }

    public func loadImage(_ filename: String) -> UIImage? {
        guard let url = url(for: filename) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    #endif

    public func delete(_ filename: String) {
        guard let url = url(for: filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Remove photos no pin references anymore. The app calls this on launch
    /// with the filenames currently in the store.
    public func reapOrphans(referenced: Set<String>) {
        guard let dir = directoryURL,
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for file in files where !referenced.contains(file) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
        }
    }
}
