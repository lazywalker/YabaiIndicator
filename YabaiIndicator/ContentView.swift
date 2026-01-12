//
//  ContentView.swift
//  YabaiIndicator
//
//  Created by Max Zhao on 26/12/2021.
//

import SwiftUI

struct SpaceButton: View {
    var space: Space

    func getText() -> String {
        switch space.type {
        case .standard:
            return "\(space.index)"
        case .fullscreen:
            return "F"
        case .divider:
            return ""
        }
    }

    func switchSpace() {
        if !space.active && space.yabaiIndex > 0 {
            do {
                try gYabaiClient.focusSpace(index: space.yabaiIndex)
                logDebug("Switched to space \(space.yabaiIndex)")
            } catch {
                logError("SpaceButton: Failed to switch space - \(error)")
                // Could show user feedback here if needed
            }
        }
    }

    var body: some View {
        if space.type == .divider {
            Divider().background(Color(.systemGray)).frame(height: 14)
        } else {
            Image(
                nsImage: generateImage(
                    symbol: getText() as NSString, active: space.active, visible: space.visible)
            ).onTapGesture {
                switchSpace()
            }.frame(width: 24, height: 16)
        }
    }
}

struct WindowSpaceButton: View {
    var space: Space
    var windows: [Window]
    var displays: [Display]

    func switchSpace() {
        if !space.active && space.yabaiIndex > 0 {
            do {
                try gYabaiClient.focusSpace(index: space.yabaiIndex)
                logDebug("WindowSpaceButton: Switched to space \(space.yabaiIndex)")
            } catch {
                logError("WindowSpaceButton: Failed to switch space - \(error)")
                // Could show user feedback here if needed
            }
        }
    }

    func getDisplay() -> Display? {
        let displayIndex = space.display - 1
        guard displayIndex >= 0 && displayIndex < displays.count else {
            return nil
        }
        return displays[displayIndex]
    }

    var body: some View {
        switch space.type {
        case .standard:
            if let display = getDisplay() {
                Image(
                    nsImage: generateImage(
                        active: space.active, visible: space.visible, windows: windows,
                        display: display)
                ).onTapGesture {
                    switchSpace()
                }.frame(width: 24, height: 16)
            } else {
                // Fallback to numeric display if display is not found
                Image(
                    nsImage: generateImage(
                        symbol: "\(space.index)" as NSString, active: space.active,
                        visible: space.visible)
                ).onTapGesture {
                    switchSpace()
                }.frame(width: 24, height: 16)
            }
        case .fullscreen:
            Image(
                nsImage: generateImage(
                    symbol: "F" as NSString, active: space.active, visible: space.visible)
            ).onTapGesture {
                switchSpace()
            }
        case .divider:
            Divider().background(Color(.systemGray)).frame(height: 14)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var spaceModel: SpaceModel
    @AppStorage("showDisplaySeparator") private var showDisplaySeparator = true
    @AppStorage("showCurrentSpaceOnly") private var showCurrentSpaceOnly = false
    @AppStorage("buttonStyle") private var buttonStyle: ButtonStyle = .numeric

    private func generateSpaces() -> [Space] {
        var shownSpaces: [Space] = []
        var lastDisplay = 0
        for space in spaceModel.spaces {
            if lastDisplay > 0 && space.display != lastDisplay {
                if showDisplaySeparator {
                    shownSpaces.append(
                        Space(
                            spaceid: 0, uuid: "", visible: true, active: false, display: 0,
                            index: 0, yabaiIndex: 0, type: .divider))
                }
            }
            if space.visible || !showCurrentSpaceOnly {
                shownSpaces.append(space)
            }
            lastDisplay = space.display
        }
        return shownSpaces
    }

    var body: some View {
        HStack(spacing: 4) {
            if let errorMessage = spaceModel.errorMessage {
                // Show error state
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.red)
                    .help(errorMessage)
                    .onTapGesture {
                        // Retry on tap
                        NotificationCenter.default.post(
                            name: NSNotification.Name("RefreshData"), object: nil)
                    }
            } else if buttonStyle == .numeric || spaceModel.displays.count > 0 {
                ForEach(generateSpaces(), id: \.self) { space in
                    switch buttonStyle {
                    case .numeric:
                        SpaceButton(space: space)
                    case .windows:
                        WindowSpaceButton(
                            space: space,
                            windows: spaceModel.windows.filter {
                                $0.spaceIndex == space.yabaiIndex
                            }, displays: spaceModel.displays)
                    }
                }
            } else {
                // Show loading state
                ProgressView()
                    .scaleEffect(0.5)
                    .help("Loading space information...")
            }
        }.padding(2)
    }
}
