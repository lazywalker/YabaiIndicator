//
//  SocketServer.swift
//  YabaiIndicator
//
//  Created for architecture refactoring
//

import Foundation
import Socket

class SocketServer {
    private var dataRefreshManager: DataRefreshManager
    private var isRunning = false
    
    init(dataRefreshManager: DataRefreshManager) {
        self.dataRefreshManager = dataRefreshManager
    }
    
    func start() async {
        guard !isRunning else { return }
        isRunning = true
        
        do {
            let socket = try Socket.create(family: .unix, type: .stream, proto: .unix)
            try socket.listen(on: Constants.Socket.socketPath)
            
            while isRunning {
                let conn = try socket.acceptClientConnection()
                let msg = try conn.readString()?.trimmingCharacters(in: .whitespacesAndNewlines)
                conn.close()
                
                // Process message
                if let message = msg {
                    await processMessage(message)
                }
            }
        } catch {
            NSLog("SocketServer Error: \(error)")
        }
        
        isRunning = false
        NSLog("SocketServer Ended")
    }
    
    func stop() {
        isRunning = false
    }
    
    private func processMessage(_ message: String) async {
        switch message {
        case "refresh":
            dataRefreshManager.refreshData()
        case "refresh spaces":
            dataRefreshManager.onSpaceRefresh()
        case "refresh windows":
            dataRefreshManager.onWindowRefresh()
        default:
            break
        }
    }
}