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
    /// Inbound create-and-pin from another app. `cling://create/<type>?…`
    /// (grammar in `ClingCreateRequest`). Folded in here so the app has a
    /// single URL routing point in `onOpenURL`.
    case create(ClingCreateRequest)

    public init?(url: URL) {
        guard url.scheme == ClingKit.urlScheme, let host = url.host else { return nil }
        // Branch on host first: create URLs carry a type path + query, not a
        // UUID, so they can't go through the id parse the others share.
        if host == ClingCreateRequest.host {
            guard let request = ClingCreateRequest(url: url) else { return nil }
            self = .create(request)
            return
        }
        guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
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
        case .create(let req):  req.url
        }
    }
}
