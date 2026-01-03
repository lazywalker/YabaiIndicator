//
//  NativeClient.swift
//  YabaiIndicator
//
//  Created by Max Zhao on 03/01/2022.
//

import ColorSync
import Foundation

enum NativeClientError: Error {
    case connectionFailed
    case displayQueryFailed
    case spaceQueryFailed
    case invalidDisplayData
    case invalidSpaceData
}

class NativeClient {
    let gConnection = SLSMainConnectionID()

    /**
    Return a list of spaces without using Yabai
     */
    func querySpaces() throws -> [Space] {
        do {
            let activeDisplayUUID = try getActiveDisplayUUID()
            let displays = try getManagedDisplaySpaces()

            return try parseSpaces(from: displays, activeDisplayUUID: activeDisplayUUID)
        } catch {
            print("NativeClient: Failed to query spaces - \(error)")
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

    func queryDisplays() throws -> [Display] {
        do {
            let rawUuids = try getManagedDisplays()
            return try parseDisplays(from: rawUuids)
        } catch {
            print("NativeClient: Failed to query displays - \(error)")
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

            // Check if display is valid
            if did == CGMainDisplayID() || CGDisplayIsActive(did) != 0 {
                let bounds = CGDisplayBounds(did)
                displays.append(
                    Display(id: UInt64(did), uuid: displayUuid as String, index: i, frame: bounds))
            }
        }
        return displays
    }
}

let gNativeClient = NativeClient()
