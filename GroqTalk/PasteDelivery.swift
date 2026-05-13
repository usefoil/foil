import Foundation

enum PasteDelivery: Equatable {
    case currentApp
    case currentAppCommandPosted
    case asyncBackground
    case asyncCommandPosted
    case asyncChoreography
    case asyncQueued
    case clipboardFallback

    var label: String {
        switch self {
        case .currentApp:
            "current app"
        case .currentAppCommandPosted:
            "current app command posted"
        case .asyncBackground:
            "original app"
        case .asyncCommandPosted:
            "original app command posted"
        case .asyncChoreography:
            "original app command posted"
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
        case .currentAppCommandPosted:
            "Paste command sent to the current app"
        case .asyncBackground:
            "Pasted into the original app"
        case .asyncCommandPosted:
            "Paste command sent to the original app"
        case .asyncChoreography:
            "Paste command sent to the original app"
        case .asyncQueued:
            "Pasted into the test target"
        case .clipboardFallback:
            "Target unavailable; text copied to clipboard"
        }
    }
}
