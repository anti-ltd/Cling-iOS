/**
 Shared constants for the Cling process family. ClingKit is compiled into the
 app, the widget extension, and the share extension; the three processes share
 state only through the App Group.
 */
import Foundation

public enum ClingKit {
    /// The App Group every Cling process reads/writes through.
    public static let appGroupID = "group.ltd.anti.cling"

    /// Deep link scheme: cling://pin/<uuid>, cling://activate/<uuid>.
    public static let urlScheme = "cling"
}
