//
//  ImageCache.swift
//  YabaiIndicator
//
//  Created for optimization
//

import Cocoa

class ImageCache {
    static let shared: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = Constants.Cache.maxCacheSize
        return cache
    }()
    
    static func image(for key: String, generator: () -> NSImage) -> NSImage {
        if let cached = shared.object(forKey: key as NSString) {
            return cached
        }
        let image = generator()
        shared.setObject(image, forKey: key as NSString)
        return image
    }
    
    static func clearCache() {
        shared.removeAllObjects()
    }
}