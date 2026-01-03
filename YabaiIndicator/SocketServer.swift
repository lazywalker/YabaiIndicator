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
    private var serverSocket: Socket? = nil

    init(dataRefreshManager: DataRefreshManager) {
        self.dataRefreshManager = dataRefreshManager
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true

        do {
            let socket = try Socket.create(family: .unix, type: .stream, proto: .unix)
            self.serverSocket = socket
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
        // Close the listening socket to break out of accept
        do {
            try serverSocket?.close()
        } catch {
            NSLog("SocketServer: Error closing socket - \(error)")
        }
        serverSocket = nil
    }

    private func processMessage(_ message: String) async {
        switch message {
        case "refresh":
            await dataRefreshManager.performAsyncRefresh()
        case "refresh spaces":
            await dataRefreshManager.performSpaceRefreshOnly()
        case "refresh windows":
            let result = await dataRefreshManager.performWindowRefresh()
            switch result {
            case .success(let windows):
                dataRefreshManager.updateWindows(windows)
            case .failure:
                dataRefreshManager.setErrorMessage("Failed to load window information")
            }
        default:
            break
        }
    }

    deinit {
        stop()
        stop()
    }
}
