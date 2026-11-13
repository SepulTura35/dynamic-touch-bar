import Foundation
import os

nonisolated enum Log {
    private static let subsystem = "com.dynamictouchbar.app"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let island = Logger(subsystem: subsystem, category: "island")
    static let touchBar = Logger(subsystem: subsystem, category: "touchbar")
    static let music = Logger(subsystem: subsystem, category: "music")
    static let system = Logger(subsystem: subsystem, category: "system")
    static let settings = Logger(subsystem: subsystem, category: "settings")
}
