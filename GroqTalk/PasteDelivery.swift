import Foundation

enum PasteDelivery: Equatable {
    case currentApp
    case asyncBackground
    case asyncChoreography
    case asyncQueued
    case clipboardFallback

    var label: String {
        switch self {
        case .currentApp:
            "current app"
        case .asyncBackground:
            "original app"
        case .asyncChoreography:
            "original app"
        case .asyncQueued:
            "test target"
        case .clipboardFallback:
            "clipboard"
        }
    }
}
