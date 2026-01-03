//
//  ImageGenerator.swift
//  YabaiIndicator
//
//  Created by Max Zhao on 29/12/2021.
//
import Foundation
import Cocoa
import SwiftUI

private func drawText(symbol: NSString, color: NSColor, size: CGSize) {
    let attrs:[NSAttributedString.Key : Any] = [.font: NSFont.systemFont(ofSize: Constants.fontSize), .foregroundColor: color]
    let boundingBox = symbol.size(withAttributes: attrs)
    let x:CGFloat = size.width / 2 - boundingBox.width / 2
    let y:CGFloat = size.height / 2 - boundingBox.height / 2

    symbol.draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: Constants.fontSize), .foregroundColor: color])
}

func generateImage(symbol: NSString, active: Bool, visible: Bool) -> NSImage {
    let cacheKey = "symbol_\(symbol)_\(active)_\(visible)"
    
    return ImageCache.image(for: cacheKey) {
        let size = Constants.imageSize
        let canvas = NSRect(origin: CGPoint.zero, size: size)
        
        let image = NSImage(size: size)
        let strokeColor = NSColor.black
        
        if active || visible{
            let imageFill = NSImage(size: size)
            let imageStroke = NSImage(size: size)

            imageFill.lockFocus()
            strokeColor.setFill()
            NSBezierPath(roundedRect: canvas, xRadius: Constants.cornerRadius, yRadius: Constants.cornerRadius).fill()
            imageFill.unlockFocus()
            imageStroke.lockFocus()
            drawText(symbol: symbol, color: strokeColor, size: size)
            imageStroke.unlockFocus()
            
            image.lockFocus()
            imageFill.draw(in: canvas, from: NSZeroRect, operation: .sourceOut, fraction: active ? 1.0 : 0.8)
            imageStroke.draw(in: canvas, from: NSZeroRect, operation: .destinationOut, fraction: active ? 1.0 : 0.8)
            image.unlockFocus()
        } else {
            image.lockFocus()
            strokeColor.setStroke()
            let path = NSBezierPath(roundedRect: canvas.insetBy(dx: 0.5, dy: 0.5), xRadius: Constants.cornerRadius, yRadius: Constants.cornerRadius)
            path.stroke()
            drawText(symbol: symbol, color: strokeColor, size: size)
            image.unlockFocus()
        }
        image.isTemplate = true
        return image
    }
}

func drawWindows(in content: NSRect, windows: [Window], display: Display) {
    let displaySize = display.frame.size
    let displayOrigin = display.frame.origin
    let contentSize = content.size
    let contentOrigin = content.origin
    let scaling = displaySize.height > displaySize.width ? displaySize.height / contentSize.height : displaySize.width / contentSize.width
    
    // Guard against division by zero and invalid values
    guard scaling > 0 && scaling.isFinite else {
        NSLog("Warning: Invalid scaling value (\(scaling)) for display. Display size: \(displaySize), Content size: \(contentSize)")
        return
    }
    
    let xoffset = (displaySize.height > displaySize.width ? (contentSize.width - displaySize.width / scaling) / 2 : 0) + contentOrigin.x
    let yoffset = (displaySize.height > displaySize.width ? 0 : (contentSize.height - displaySize.height / scaling) / 2) + contentOrigin.y
    
    let scalingFactor = 1/scaling
    let transform = NSAffineTransform()
    transform.scale(by: scalingFactor)
    transform.translateX(by: xoffset / scalingFactor, yBy: yoffset / scalingFactor)
    // plot single windows
    for window in windows.reversed() {
        let fixedOrigin = NSPoint(x: window.frame.origin.x - displayOrigin.x, y: displaySize.height - (window.frame.origin.y - displayOrigin.y + window.frame.height))
        let windowOrigin = transform.transform(fixedOrigin)
        let windowSize = transform.transform(window.frame.size)
        let windowRect = NSRect(origin: windowOrigin, size: windowSize)
        let windowPath = NSBezierPath(rect: windowRect)
        windowPath.fill()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        windowPath.lineWidth = 1.5
        windowPath.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

func generateImage(active: Bool, visible: Bool, windows: [Window], display: Display) -> NSImage {
    // Create a more comprehensive cache key that includes window positions
    let windowPositions = windows.map { "\($0.frame.origin.x),\($0.frame.origin.y),\($0.frame.size.width),\($0.frame.size.height)" }.joined(separator: "|")
    let cacheKey = "windows_\(active)_\(visible)_\(display.id)_\(windows.count)_\(windowPositions.hashValue)"
    
    return ImageCache.image(for: cacheKey) {
        let size = Constants.imageSize
        let canvas = NSRect(origin: CGPoint.zero, size: size)
        let bounds = NSBezierPath(rect: canvas.insetBy(dx: 4, dy: 4))
        
        
        let image = NSImage(size: size)
        let strokeColor = NSColor.black
        
        if active || visible{
            let imageFill = NSImage(size: size)
            let imageStroke = NSImage(size: size)

            imageFill.lockFocus()
            strokeColor.setFill()
            NSBezierPath(roundedRect: canvas, xRadius: Constants.cornerRadius, yRadius: Constants.cornerRadius).fill()
            imageFill.unlockFocus()
            
            imageStroke.lockFocus()
            drawWindows(in: canvas, windows: windows, display: display)
            imageStroke.unlockFocus()
            
            image.lockFocus()
            imageFill.draw(in: canvas, from: NSZeroRect, operation: .sourceOut, fraction: active ? 1.0 : 0.8)
            
            bounds.setClip()
            imageStroke.draw(in: canvas, from: NSZeroRect, operation: .destinationOut, fraction: active ? 1.0 : 0.8)
            image.unlockFocus()
        } else {
            image.lockFocus()
            strokeColor.setStroke()
            let path = NSBezierPath(roundedRect: canvas.insetBy(dx: 0.5, dy: 0.5), xRadius: Constants.cornerRadius, yRadius: Constants.cornerRadius)
            path.stroke()

            bounds.setClip()
            drawWindows(in: canvas, windows: windows, display: display)
            image.unlockFocus()
        }
        image.isTemplate = true
        return image
    }
}
