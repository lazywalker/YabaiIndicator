//
//  NativeClient.swift
//  YabaiIndicator
//
//  Created by Max Zhao on 03/01/2022.
//
/// Native client for querying macOS system information without yabai.
/// Uses private SLS APIs to fetch display and space information directly from the system.

import ColorSync
import Foundation

enum NativeClientError: Error, CustomStringConvertible {
    case connectionFailed
    case displayQueryFailed
    case spaceQueryFailed
    case invalidDisplayData
    case invalidSpaceData
    case validationError(String)

    var description: String {
        switch self {
        case .connectionFailed: return "SLS connection failed"
        case .displayQueryFailed: return "Display query failed"
        case .spaceQueryFailed: return "Space query failed"
        case .invalidDisplayData: return "Invalid display data"
        case .invalidSpaceData: return "Invalid space data"
        case .validationError(let msg): return "Validation error: \(msg)"
        }
    }
}

class NativeClient {
    let gConnection = SLSMainConnectionID()

    init() {
        logDebug("NativeClient initialized with connection ID: \(gConnection)")
    }

    /// Queries the list of spaces from macOS system.
    /// Returns all available spaces across all displays without requiring yabai.
    /// - Returns: Array of Space objects with display and visibility information
    /// - Throws: NativeClientError if connection or parsing fails
    ///
    /// Each space includes:
    /// - spaceid: Unique space ID
    /// - uuid: Space UUID for identification
    /// - visible: Whether space is currently visible
    /// - active: Whether space is the active workspace
    /// - display: Display index
    /// - index: Space index within display (for standard spaces)
    /// - yabaiIndex: Global space index across all displays
    /// - type: Space type (standard, fullscreen, etc.)
    func querySpaces() throws -> [Space] {
        do {
            let activeDisplayUUID = try getActiveDisplayUUID()
            let displays = try getManagedDisplaySpaces()

            let spaces = try parseSpaces(from: displays, activeDisplayUUID: activeDisplayUUID)
            logDebug("NativeClient: Queried \(spaces.count) spaces")
            return spaces
        } catch {
            logError("NativeClient: Failed to query spaces - \(error)")
            throw error
        }
    }

    private func getActiveDisplayUUID() throws -> String {
        guard
            let uuid = SLSCopyActiveMenuBarDisplayIdentifier(gConnection)?.takeRetainedValue()
                as String?
        else {
            throw NativeClientError.connectionFailed
        }
        return uuid
    }

    private func getManagedDisplaySpaces() throws -> [AnyObject] {
        guard
            let displays = SLSCopyManagedDisplaySpaces(gConnection)?.takeRetainedValue()
                as? [AnyObject]
        else {
            throw NativeClientError.displayQueryFailed
        }
        return displays
    }

    private func parseSpaces(from displays: [AnyObject], activeDisplayUUID: String) throws
        -> [Space]
    {
        var spaceIncr = 0
        var totalSpaces = 0
        var spaces: [Space] = []

        for (dindex, display) in displays.enumerated() {
            guard let displayDict = display as? NSDictionary else {
                throw NativeClientError.invalidDisplayData
            }

            let displaySpaces = displayDict["Spaces"] as? [NSDictionary] ?? []
            let current = displayDict["Current Space"] as? NSDictionary
            let currentUUID = current?["uuid"] as? String ?? ""
            let displayUUID = displayDict["Display Identifier"] as? String ?? ""
            let activeDisplay = activeDisplayUUID == displayUUID

            for nsSpace in displaySpaces {
                let spaceId = nsSpace["id64"] as? UInt64 ?? 0
                let spaceUUID = nsSpace["uuid"] as? String ?? ""
                let visible = spaceUUID == currentUUID
                let active = visible && activeDisplay
                let spaceType = nsSpace["type"] as? Int ?? 0

                // Validate space type is reasonable
                guard spaceType >= 0 && spaceType <= 3 else {
                    continue  // Skip invalid space types
                }

                var spaceIndex = 0
                totalSpaces += 1
                if spaceType == 0 {
                    spaceIncr += 1
                    spaceIndex = spaceIncr
                }

                let spaceTypeEnum = SpaceType(rawValue: spaceType) ?? SpaceType.standard
                spaces.append(
                    Space(
                        spaceid: spaceId, uuid: spaceUUID, visible: visible, active: active,
                        display: dindex + 1, index: spaceIndex, yabaiIndex: totalSpaces,
                        type: spaceTypeEnum))
            }
        }
        return spaces
    }

    /// Queries available displays from the system.
    /// Validates that displays are active and have valid frame dimensions.
    /// - Returns: Array of Display objects with id, uuid, index, and frame information
    /// - Throws: NativeClientError if display query fails
    ///
    /// Each display includes:
    /// - id: CGDisplay ID (Core Graphics display identifier)
    /// - uuid: Unique display UUID
    /// - index: Display index (0-based)
    /// - frame: Display bounds (x, y, width, height)
    ///
    /// Only returns displays that are active or are the main display
    func queryDisplays() throws -> [Display] {
        do {
            let rawUuids = try getManagedDisplays()
            let displays = try parseDisplays(from: rawUuids)
            logDebug("NativeClient: Queried \(displays.count) displays")
            return displays
        } catch {
            logError("NativeClient: Failed to query displays - \(error)")
            throw error
        }
    }

    private func getManagedDisplays() throws -> [CFString] {
        guard let uuids = SLSCopyManagedDisplays(gConnection)?.takeRetainedValue() as? [CFString]
        else {
            throw NativeClientError.displayQueryFailed
        }
        return uuids
    }

    private func parseDisplays(from uuids: [CFString]) throws -> [Display] {
        var displays: [Display] = []
        for (i, displayUuid) in uuids.enumerated() {
            let cfuuid = CFUUIDCreateFromString(nil, displayUuid)
            let did = CGDisplayGetDisplayIDFromUUID(cfuuid)

            // Validate display: must be main display or active
            guard did == CGMainDisplayID() || CGDisplayIsActive(did) != 0 else {
                continue
            }

            let bounds = CGDisplayBounds(did)

            // Validate frame has positive dimensions
            guard bounds.width > 0, bounds.height > 0 else {
                continue
            }

            displays.append(
                Display(id: UInt64(did), uuid: displayUuid as String, index: i, frame: bounds))
        }
        return displays
    }
}

let gNativeClient = NativeClient()
