//
//  YabaiClient.swift
//  YabaiIndicator
//
//  Created by Max Zhao on 01/01/2022.
//

import SwiftUI

enum YabaiClientError: Error {
    case socketConnectionFailed
    case jsonParsingFailed
    case invalidResponse
    case yabaiCommandFailed(Int)
}

struct YabaiResponse {
    let error: Int
    let response: Any
}

class YabaiClient {

    func _yabaiSocketCall(_ args: [String]) throws -> (Int, String) {
        var cresp: UnsafeMutablePointer<CChar>? = nil
        var cargs = args.map { strdup($0) }
        defer {
            for ptr in cargs { free(ptr) }
            free(cresp)
        }

        let ret = send_message(Int32(args.count), &cargs, &cresp)

        guard ret == 0 else {
            throw YabaiClientError.yabaiCommandFailed(Int(ret))
        }

        var response = ""
        if let r = cresp {
            response = String(cString: r)
        }
        return (Int(ret), response)
    }

    @discardableResult
    func yabaiSocketCall(_ args: String...) throws -> YabaiResponse {
        let (e, m) = try _yabaiSocketCall(args)
        var resp: Any = []
        if m.count > 0 {
            if let data = m.data(using: .utf8) {
                do {
                    resp = try JSONSerialization.jsonObject(with: data, options: [])
                } catch {
                    print("YabaiClient: JSON parsing error - \(error)")
                    throw YabaiClientError.jsonParsingFailed
                }
            }
        }
        let r = YabaiResponse(error: e, response: resp)
        return r
    }

    func focusSpace(index: Int) throws {
        try yabaiSocketCall(
            "-m", "space", "--focus", "\(index)")
    }

    func queryWindows() throws -> [Window] {
        let response = try yabaiSocketCall("-m", "query", "--windows")
        guard let r = response.response as? [[String: Any]] else {
            throw YabaiClientError.invalidResponse
        }

        let windows = r.compactMap { dict -> Window? in
            guard let id = dict["id"] as? UInt64,
                let pid = dict["pid"] as? UInt64,
                let app = dict["app"] as? String,
                let title = dict["title"] as? String,
                let frameDict = dict["frame"] as? [String: Double],
                let x = frameDict["x"],
                let y = frameDict["y"],
                let w = frameDict["w"],
                let h = frameDict["h"],
                let displayIndex = dict["display"] as? Int,
                let spaceIndex = dict["space"] as? Int
            else {
                return nil
            }
            return Window(
                id: id,
                pid: pid,
                app: app,
                title: title,
                frame: NSRect(x: x, y: y, width: w, height: h),
                displayIndex: displayIndex,
                spaceIndex: spaceIndex)
        }
        return windows
    }
}

let gYabaiClient = YabaiClient()
