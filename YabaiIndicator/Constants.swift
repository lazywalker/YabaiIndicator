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
        static let maxCacheSize: Int = 50 // Maximum number of cached images
    }
    
    struct Socket {
        static let socketPath = "/tmp/yabai-indicator.socket"
        static let receiverQueueLabel = "yabai-indicator.socket.receiver"
    }
}