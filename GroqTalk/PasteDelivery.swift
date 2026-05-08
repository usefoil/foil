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

    var userMessage: String {
        switch self {
        case .currentApp:
            "Pasted into the current app"
        case .asyncBackground:
            "Pasted into the original app"
        case .asyncChoreography:
            "Pasted into the original app"
        case .asyncQueued:
            "Pasted into the test target"
        case .clipboardFallback:
            "Target unavailable; text copied to clipboard"
        }
    }
}
