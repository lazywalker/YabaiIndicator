//
//  Constants.swift
//  YabaiIndicator
//
//  Created for optimization
//

import Cocoa

struct Constants {
    static let statusBarHeight: CGFloat = 22
    static let itemWidth: CGFloat = 30
    static let cornerRadius: CGFloat = 6
    static let imageSize = CGSize(width: 24, height: 16)
    static let fontSize: CGFloat = 11

    struct Cache {
        static let maxCacheSize: Int = 50  // Maximum number of cached images
    }

    struct Socket {
        static let socketPath = "/tmp/yabai-indicator.socket"
        static let receiverQueueLabel = "yabai-indicator.socket.receiver"
        static let maxArgumentLength: Int = 1024  // Max length per argument
        static let maxArgumentCount: Int = 50  // Max number of arguments
    }

    struct Validation {
        static let maxSpaceIndex: Int = 100  // Reasonable max space index
        static let maxWindowTitleLength: Int = 500  // Max window title length
        static let socketReadTimeoutSeconds: TimeInterval = 5.0
    }
}
