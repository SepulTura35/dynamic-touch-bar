import Foundation

nonisolated enum AnimationStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case smooth, bouncy, snappy, gentle, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smooth: "Smooth"
        case .bouncy: "Bouncy"
        case .snappy: "Snappy"
        case .gentle: "Gentle"
        case .custom: "Custom"
        }
    }

    func parameters(custom: SpringParameters) -> SpringParameters {
        switch self {
        case .smooth: .smooth
        case .bouncy: .bouncy
        case .snappy: .snappy
        case .gentle: .gentle
        case .custom: custom
        }
    }
}
