//
//  YabaiClient.swift
//  YabaiIndicator
//
//  Created by Max Zhao on 01/01/2022.
//

import SwiftUI

enum YabaiClientError: Error, CustomStringConvertible {
    case socketConnectionFailed
    case jsonParsingFailed
    case invalidResponse
    case yabaiCommandFailed(Int)
    case invalidInput(String)

    var description: String {
        switch self {
        case .socketConnectionFailed: return "Socket connection failed"
        case .jsonParsingFailed: return "JSON parsing failed"
        case .invalidResponse: return "Invalid response"
        case .yabaiCommandFailed(let code): return "Yabai command failed with code \(code)"
        case .invalidInput(let msg): return "Invalid input: \(msg)"
        }
    }
}

struct YabaiResponse {
    let error: Int
    let response: Any
}

class YabaiClient {

    init() {
        logDebug("YabaiClient initialized")
    }

    /// Internal socket communication with input validation
    /// - Parameter args: Command arguments to send
    /// - Returns: Tuple of (error code, response string)
    /// - Throws: YabaiClientError if validation fails or socket communication fails
    ///
    /// Validates all arguments for security and length constraints
    func _yabaiSocketCall(_ args: [String]) throws -> (Int, String) {
        // Input validation
        guard !args.isEmpty else {
            throw YabaiClientError.invalidInput("Empty arguments array")
        }

        guard args.count <= Constants.Socket.maxArgumentCount else {
            throw YabaiClientError.invalidInput(
                "Exceeded maximum argument count: \(Constants.Socket.maxArgumentCount)")
        }

        for (index, arg) in args.enumerated() {
            // Security: prevent null byte injection
            if arg.contains("\0") {
                throw YabaiClientError.invalidInput("Null bytes not allowed in argument #\(index)")
            }

            // Length validation
            if arg.count > Constants.Socket.maxArgumentLength {
                throw YabaiClientError.invalidInput(
                    "Argument #\(index) exceeds maximum length: \(Constants.Socket.maxArgumentLength)"
                )
            }
        }

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

    /// Sends a command to yabai via socket and returns a parsed response
    /// - Parameter args: Variable number of string arguments for the yabai command
    /// - Returns: YabaiResponse containing error code and parsed JSON response
    /// - Throws: YabaiClientError if socket communication fails, JSON parsing fails, or input validation fails
    ///
    /// Example usage:
    /// ```swift
    /// let response = try yabaiClient.yabaiSocketCall("-m", "query", "--spaces")
    /// ```
    @discardableResult
    func yabaiSocketCall(_ args: String...) throws -> YabaiResponse {
        let (e, m) = try _yabaiSocketCall(args)
        var resp: Any = []
        if m.count > 0 {
            if let data = m.data(using: .utf8) {
                do {
                    resp = try JSONSerialization.jsonObject(with: data, options: [])
                } catch {
                    logError("YabaiClient: JSON parsing error - \(error)")
                    throw YabaiClientError.jsonParsingFailed
                }
            }
        }
        let r = YabaiResponse(error: e, response: resp)
        return r
    }

    /// Focuses on a specific space by index
    /// - Parameter index: The space index (must be > 0 and ≤ Constants.Validation.maxSpaceIndex)
    /// - Throws: YabaiClientError if index is invalid or focus command fails
    ///
    /// Space indices are 1-based and correspond to workspace numbers in yabai
    func focusSpace(index: Int) throws {
        guard index > 0 else {
            throw YabaiClientError.invalidInput("Space index must be > 0")
        }
        guard index <= Constants.Validation.maxSpaceIndex else {
            throw YabaiClientError.invalidInput(
                "Space index exceeds maximum: \(Constants.Validation.maxSpaceIndex)")
        }
        logDebug("YabaiClient: Focusing space \(index)")
        try yabaiSocketCall(
            "-m", "space", "--focus", "\(index)")
    }

    /// Queries all open windows from yabai
    /// - Returns: Array of Window structures with metadata
    /// - Throws: YabaiClientError if query fails or response format is invalid
    ///
    /// Window data includes: window ID, process ID, app name, title, frame coordinates, display and space indices
    /// Invalid or malformed window entries are silently filtered out
    func queryWindows() throws -> [Window] {
        let response = try yabaiSocketCall("-m", "query", "--windows")
        guard let r = response.response as? [[String: Any]] else {
            logError("YabaiClient: Invalid response format for queryWindows")
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

            // Validate window title length (prevent UI rendering issues)
            guard title.count <= Constants.Validation.maxWindowTitleLength else {
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
        logDebug("YabaiClient: Queried \(windows.count) windows")
        return windows
    }
}

let gYabaiClient = YabaiClient()
