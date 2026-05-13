import Foundation

enum WhiteboardConfiguration {
    static let showsGridDefaultsKey = "whiteboard.showsGrid"
    static let gridSpacingDefaultsKey = "whiteboard.gridSpacing"
    static let connectorArrowsDefaultsKey = "whiteboard.connectorArrows"
    static let connectorRoutingDefaultsKey = "whiteboard.connectorRouting"
    static let stickyFillDefaultsKey = "whiteboard.stickyFill"

    static let defaultShowsGrid = true
    static let defaultGridSpacing = 24
    static let minimumGridSpacing = 8
    static let maximumGridSpacing = 96
    static let defaultConnectorArrows = true
    static let defaultConnectorRouting = WhiteboardConnectorRouting.orthogonal
    static let defaultStickyFill = WhiteboardFill.yellow

    static func showsGrid(defaults: UserDefaults = .standard) -> Bool {
        guard let stored = defaults.object(forKey: showsGridDefaultsKey) as? NSNumber else {
            return defaultShowsGrid
        }
        return stored.boolValue
    }

    static func gridSpacing(defaults: UserDefaults = .standard) -> Int {
        clampedGridSpacing(defaults.object(forKey: gridSpacingDefaultsKey) as? Int ?? defaultGridSpacing)
    }

    static func connectorArrows(defaults: UserDefaults = .standard) -> Bool {
        guard let stored = defaults.object(forKey: connectorArrowsDefaultsKey) as? NSNumber else {
            return defaultConnectorArrows
        }
        return stored.boolValue
    }

    static func connectorRouting(defaults: UserDefaults = .standard) -> WhiteboardConnectorRouting {
        connectorRouting(rawValue: defaults.string(forKey: connectorRoutingDefaultsKey))
    }

    static func stickyFill(defaults: UserDefaults = .standard) -> WhiteboardFill {
        stickyFill(rawValue: defaults.string(forKey: stickyFillDefaultsKey))
    }

    static func clampedGridSpacing(_ value: Int) -> Int {
        min(max(value, minimumGridSpacing), maximumGridSpacing)
    }

    static func connectorRouting(rawValue: String?) -> WhiteboardConnectorRouting {
        guard let rawValue,
              let routing = WhiteboardConnectorRouting(rawValue: rawValue) else {
            return defaultConnectorRouting
        }
        return routing
    }

    static func stickyFill(rawValue: String?) -> WhiteboardFill {
        guard let rawValue,
              let fill = WhiteboardFill(rawValue: rawValue) else {
            return defaultStickyFill
        }
        return fill
    }
}
