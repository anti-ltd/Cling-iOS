/**
 The `cling://` URL vocabulary. Live Activity taps, renewal notifications, and
 the share extension all route back into the app through these.
 */
import Foundation

public enum DeepLink: Equatable, Sendable {
    /// Open the pin's detail screen. `cling://pin/<uuid>`
    case pin(UUID)
    /// (Re)start the pin's Live Activity — renewal taps and share-extension
    /// handoff. `cling://activate/<uuid>`
    case activate(UUID)

    public init?(url: URL) {
        guard url.scheme == ClingKit.urlScheme,
              let host = url.host,
              let id = UUID(uuidString: url.lastPathComponent) else { return nil }
        switch host {
        case "pin":      self = .pin(id)
        case "activate": self = .activate(id)
        default:         return nil
        }
    }

    public var url: URL {
        switch self {
        case .pin(let id):      URL(string: "\(ClingKit.urlScheme)://pin/\(id.uuidString)")!
        case .activate(let id): URL(string: "\(ClingKit.urlScheme)://activate/\(id.uuidString)")!
        }
    }
}
