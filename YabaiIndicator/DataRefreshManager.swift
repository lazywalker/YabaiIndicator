//
//  DataRefreshManager.swift
//  YabaiIndicator
//
//  Created for architecture refactoring
//

import Combine
import Foundation

class DataRefreshManager {
    private var spaceModel: SpaceModel
    private let receiverQueue = DispatchQueue(label: Constants.Socket.receiverQueueLabel)

    init(spaceModel: SpaceModel) {
        self.spaceModel = spaceModel
    }

    @objc func refreshData() {
        receiverQueue.async { [weak self] in
            self?.onSpaceRefresh()
            self?.onWindowRefresh()
        }
    }

    func onSpaceRefresh() {
        do {
            let displays = try gNativeClient.queryDisplays()
            let spaceElems = try gNativeClient.querySpaces()

            DispatchQueue.main.async { [weak self] in
                self?.spaceModel.displays = displays
                self?.spaceModel.spaces = spaceElems
                self?.spaceModel.errorMessage = nil
            }
        } catch {
            print("DataRefreshManager: Failed to refresh space data - \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.spaceModel.errorMessage = "Failed to load space information"
            }
        }
    }

    func onWindowRefresh() {
        if UserDefaults.standard.buttonStyle == .windows {
            do {
                let windows = try gYabaiClient.queryWindows()
                DispatchQueue.main.async { [weak self] in
                    self?.spaceModel.windows = windows
                    self?.spaceModel.errorMessage = nil
                }
            } catch {
                print("DataRefreshManager: Failed to refresh window data - \(error)")
                DispatchQueue.main.async { [weak self] in
                    self?.spaceModel.errorMessage = "Failed to load window information"
                }
            }
        }
    }

    @objc func onSpaceChanged(_ notification: Notification) {
        onSpaceRefresh()
    }

    @objc func onDisplayChanged(_ notification: Notification) {
        onSpaceRefresh()
    }
}
