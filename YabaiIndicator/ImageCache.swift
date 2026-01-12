//
//  ImageCache.swift
//  YabaiIndicator
//
//  Created for optimization
//

import Cocoa

class ImageCache {
    private static let cacheQueue = DispatchQueue(
        label: "com.yabaiindicator.imagecache", attributes: .concurrent)

    static let shared: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = Constants.Cache.maxCacheSize
        return cache
    }()

    static func image(for key: String, generator: () -> NSImage) -> NSImage {
        // Check cache first (read can be concurrent)
        if let cached = cacheQueue.sync(execute: { shared.object(forKey: key as NSString) }) {
            return cached
        }

        // Generate image - must be on main thread for NSImage operations
        let image: NSImage
        if Thread.isMainThread {
            image = generator()
        } else {
            image = DispatchQueue.main.sync {
                generator()
            }
        }

        // Store in cache (write with barrier)
        cacheQueue.async(flags: .barrier) {
            shared.setObject(image, forKey: key as NSString)
        }

        return image
    }

    static func clearCache() {
        cacheQueue.async(flags: .barrier) {
            shared.removeAllObjects()
            logDebug("Image cache cleared")
        }
    }
}
