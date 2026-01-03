//
//  DataRefreshManager.swift
//  YabaiIndicator
//
//  Created for architecture refactoring
//

import Foundation
import Combine

class DataRefreshManager {
    private var spaceModel: SpaceModel
    private let receiverQueue = DispatchQueue(label: Constants.Socket.receiverQueueLabel)
    
    init(spaceModel: SpaceModel) {
        self.spaceModel = spaceModel
    }
    
    func refreshData() {
        receiverQueue.async { [weak self] in
            self?.onSpaceRefresh()
            self?.onWindowRefresh()
        }
    }
    
    func onSpaceRefresh() {
        let displays = gNativeClient.queryDisplays()
        let spaceElems = gNativeClient.querySpaces()
        
        DispatchQueue.main.async { [weak self] in
            self?.spaceModel.displays = displays
            self?.spaceModel.spaces = spaceElems
        }
    }
    
    func onWindowRefresh() {
        if UserDefaults.standard.buttonStyle == .windows {
            let windows = gYabaiClient.queryWindows()
            DispatchQueue.main.async { [weak self] in
                self?.spaceModel.windows = windows
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