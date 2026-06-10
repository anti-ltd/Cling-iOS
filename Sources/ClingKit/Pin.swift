/**
 `Pin`: one pinned thing. The store's unit of persistence and the activity
 coordinator's unit of work.
 */
import Foundation

/// Where a pin is in its Live Activity life.
public enum PinStatus: String, Codable, Sendable, Hashable {
    /// Saved but not yet live — e.g. created by the share extension, which
    /// cannot start activities (iOS rule). The app activates these on launch.
    case pending
    /// Live in the Dynamic Island / on the lock screen.
    case live
    /// Hit the 8h activity ceiling (or its stale date); still on the lock
    /// screen but no longer fresh. Honest UI shows this, not a fake "live".
    case stale
    /// Dismissed or expired out entirely.
    case ended
}

public struct Pin: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var payload: PinPayload
    public var createdAt: Date
    /// The user-meaningful end, when there is one (a timer's zero moment).
    /// Distinct from the system stale date the coordinator computes.
    public var endDate: Date?
    public var appearance: PinAppearance
    /// ActivityKit's id while the pin is live; nil otherwise.
    public var activityID: String?
    public var status: PinStatus
    /// When the current activity goes stale — the system 8h ceiling or the
    /// pin's own end, whichever comes first. Set on every (re)activation;
    /// what the renewal notification and the expiry badge key off.
    public var staleDate: Date?

    public init(
        id: UUID = UUID(),
        payload: PinPayload,
        createdAt: Date = .now,
        endDate: Date? = nil,
        appearance: PinAppearance,
        activityID: String? = nil,
        status: PinStatus = .pending,
        staleDate: Date? = nil
    ) {
        self.id = id
        self.payload = payload
        self.createdAt = createdAt
        self.endDate = endDate
        self.appearance = appearance
        self.activityID = activityID
        self.status = status
        self.staleDate = staleDate
    }

    /// True when the activity's life is capped by the system ceiling rather
    /// than the pin's own end — i.e. renewing it buys more time.
    public var isRenewable: Bool {
        guard let staleDate else { return false }
        guard let endDate else { return true }
        return staleDate < endDate
    }

    public var typeID: PinTypeID { payload.typeID }
}
