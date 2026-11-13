import Foundation

/// Touch Bar availability, derived from the public `hw.model` sysctl.
///
/// There is no public API that answers "does this Mac have a Touch Bar?", so we match the
/// documented list of Touch Bar MacBook Pro model identifiers. Nothing here touches private
/// frameworks or hardware interfaces.
nonisolated struct HardwareInfo: Equatable, Sendable {
    let modelIdentifier: String
    let hasTouchBar: Bool
    let marketingName: String?

    static let touchBarModels: [String: String] = [
        "MacBookPro13,2": "MacBook Pro (13-inch, 2016, Four Thunderbolt 3 Ports)",
        "MacBookPro13,3": "MacBook Pro (15-inch, 2016)",
        "MacBookPro14,2": "MacBook Pro (13-inch, 2017, Four Thunderbolt 3 Ports)",
        "MacBookPro14,3": "MacBook Pro (15-inch, 2017)",
        "MacBookPro15,1": "MacBook Pro (15-inch, 2018/2019)",
        "MacBookPro15,2": "MacBook Pro (13-inch, 2018/2019, Four Thunderbolt 3 Ports)",
        "MacBookPro15,3": "MacBook Pro (15-inch, 2019, Vega)",
        "MacBookPro15,4": "MacBook Pro (13-inch, 2019, Two Thunderbolt 3 Ports)",
        "MacBookPro16,1": "MacBook Pro (16-inch, 2019)",
        "MacBookPro16,2": "MacBook Pro (13-inch, 2020, Four Thunderbolt 3 Ports)",
        "MacBookPro16,3": "MacBook Pro (13-inch, 2020, Two Thunderbolt 3 Ports)",
        "MacBookPro16,4": "MacBook Pro (16-inch, 2019, Radeon Pro 5600M)",
        "MacBookPro17,1": "MacBook Pro (13-inch, M1, 2020)",
        "Mac14,7": "MacBook Pro (13-inch, M2, 2022)",
    ]

    init(modelIdentifier: String) {
        self.modelIdentifier = modelIdentifier
        self.marketingName = Self.touchBarModels[modelIdentifier]
        self.hasTouchBar = marketingName != nil
    }

    static let current = HardwareInfo(modelIdentifier: readModelIdentifier())

    static func readModelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "Unknown" }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    var summary: String {
        if let marketingName { return "Touch Bar detected — \(marketingName)" }
        return "No physical Touch Bar detected on this Mac (\(modelIdentifier))"
    }
}
