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
    private let serverLock = NSLock()

    init(dataRefreshManager: DataRefreshManager) {
        self.dataRefreshManager = dataRefreshManager
        logDebug("SocketServer initialized")
    }

    func start() async {
        serverLock.lock()
        guard !isRunning else {
            serverLock.unlock()
            logWarning("SocketServer already running")
            return
        }
        isRunning = true
        serverLock.unlock()

        logInfo("SocketServer starting on \(Constants.Socket.socketPath)")

        do {
            // Remove existing socket file if exists
            try? FileManager.default.removeItem(atPath: Constants.Socket.socketPath)

            let socket = try Socket.create(family: .unix, type: .stream, proto: .unix)
            serverLock.lock()
            self.serverSocket = socket
            serverLock.unlock()

            try socket.listen(on: Constants.Socket.socketPath)
            logInfo("SocketServer listening successfully")

            while isRunning {
                do {
                    let conn = try socket.acceptClientConnection()
                    let msg = try conn.readString()?.trimmingCharacters(in: .whitespacesAndNewlines)
                    conn.close()

                    // Process message
                    if let message = msg {
                        Logger.shared.trackSocketMessage()
                        logDebug("Socket received message: '\(message)'")
                        await processMessage(message)
                    }
                } catch {
                    if isRunning {
                        logError("Socket accept/read error: \(error)")
                    }
                }
            }
        } catch {
            logError("SocketServer fatal error: \(error)")
        }

        serverLock.lock()
        isRunning = false
        serverLock.unlock()
        logInfo("SocketServer stopped")
    }

    func stop() {
        serverLock.lock()
        defer { serverLock.unlock() }

        guard isRunning else { return }

        logInfo("SocketServer stopping...")
        isRunning = false

        // Close the listening socket to break out of accept
        if let socket = serverSocket {
            socket.close()
            serverSocket = nil
        }
    }

    private func processMessage(_ message: String) async {
        let startTime = Date()

        switch message {
        case "refresh":
            logDebug("Processing 'refresh' command")
            await dataRefreshManager.performAsyncRefresh()
        case "refresh spaces":
            logDebug("Processing 'refresh spaces' command")
            await dataRefreshManager.performSpaceRefreshOnly()
        case "refresh windows":
            logDebug("Processing 'refresh windows' command")
            let result = await dataRefreshManager.performWindowRefresh()
            switch result {
            case .success(let windows):
                dataRefreshManager.updateWindows(windows)
            case .failure:
                dataRefreshManager.setErrorMessage("Failed to load window information")
            }
        default:
            logWarning("Unknown socket message: '\(message)'")
        }

        let duration = Date().timeIntervalSince(startTime)
        logDebug("Socket message '\(message)' processed in \(String(format: "%.3f", duration))s")
    }

    deinit {
        logDebug("SocketServer deinit")
        stop()
    }
}
