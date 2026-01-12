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
    private var currentTask: Task<Void, Never>? = nil
    private var lastRefreshTime: Date = Date.distantPast
    private let refreshLock = NSLock()

    init(spaceModel: SpaceModel) {
        self.spaceModel = spaceModel
        logDebug("DataRefreshManager initialized")
    }

    @objc func refreshData() {
        refreshLock.lock()
        defer { refreshLock.unlock() }

        // Debounce rapid refresh calls to prevent excessive updates
        let now = Date()
        guard now.timeIntervalSince(lastRefreshTime) > 0.1 else {
            logDebug("Refresh debounced (too frequent)")
            return
        }
        lastRefreshTime = now

        // Cancel any pending refresh task to prevent overlapping requests
        currentTask?.cancel()
        currentTask = nil

        Logger.shared.trackRefresh()
        logDebug("Starting data refresh...")

        // Store the task so it can be cancelled if the manager is deallocated
        currentTask = Task { [weak self] in
            guard let self = self else {
                logWarning("DataRefreshManager deallocated during refresh")
                return
            }

            do {
                try Task.checkCancellation()
                await self.performAsyncRefresh()
            } catch is CancellationError {
                logDebug("Refresh task was cancelled")
            } catch {
                logError("Unexpected error during refresh: \(error)")
            }

            // Clear reference when done
            Task { @MainActor in self.currentTask = nil }
        }
    }

    func performAsyncRefresh() async {
        let startTime = Date()
        logDebug("Performing async refresh...")

        // Perform both space and window refresh concurrently
        async let spaceRefresh = performSpaceRefresh()
        async let windowRefresh = performWindowRefresh()

        // Wait for both to complete
        let (spaceResult, windowResult) = await (spaceRefresh, windowRefresh)

        let duration = Date().timeIntervalSince(startTime)
        logDebug("Async refresh completed in \(String(format: "%.3f", duration))s")

        // Update UI on main thread
        await MainActor.run {
            if case .success(let (displays, spaces)) = spaceResult {
                self.spaceModel.displays = displays
                self.spaceModel.spaces = spaces
                logDebug("Updated model: \(displays.count) displays, \(spaces.count) spaces")
            }

            if case .success(let windows) = windowResult {
                self.spaceModel.windows = windows
                logDebug("Updated model: \(windows.count) windows")
            }

            // Set error message if both failed
            if case .failure(let error) = spaceResult, case .failure = windowResult {
                self.spaceModel.errorMessage = "Failed to load space and window information"
                logError("Both space and window refresh failed: \(error)")
            } else if case .failure(let error) = spaceResult {
                self.spaceModel.errorMessage = "Failed to load space information"
                logError("Space refresh failed: \(error)")
            } else if case .failure(let error) = windowResult {
                self.spaceModel.errorMessage = "Failed to load window information"
                logWarning("Window refresh failed: \(error)")
            } else {
                self.spaceModel.errorMessage = nil
            }
        }
    }

    private func performSpaceRefresh() async -> Result<
        (displays: [Display], spaces: [Space]), Error
    > {
        do {
            async let displaysTask = Task { try gNativeClient.queryDisplays() }
            async let spacesTask = Task { try gNativeClient.querySpaces() }

            let displays = try await displaysTask.value
            let spaces = try await spacesTask.value

            logDebug("Space refresh successful: \(displays.count) displays, \(spaces.count) spaces")
            return .success((displays: displays, spaces: spaces))
        } catch {
            logError("Failed to refresh space data: \(error)")
            return .failure(error)
        }
    }

    func performWindowRefresh() async -> Result<[Window], Error> {
        guard UserDefaults.standard.buttonStyle == .windows else {
            return .success([])
        }

        do {
            let windows = try await Task { try gYabaiClient.queryWindows() }.value
            logDebug("Window refresh successful: \(windows.count) windows")
            return .success(windows)
        } catch {
            logWarning("Failed to refresh window data: \(error)")
            return .failure(error)
        }
    }

    @objc func onSpaceChanged(_ notification: Notification) {
        Logger.shared.trackSpaceChange()
        logInfo("Space changed notification received: \(notification.name.rawValue)")

        Task { [weak self] in
            await self?.performSpaceRefreshOnly()
        }
    }

    @objc func onDisplayChanged(_ notification: Notification) {
        Logger.shared.trackDisplayChange()
        logInfo("Display changed notification received: \(notification.name.rawValue)")

        Task { [weak self] in
            await self?.performSpaceRefreshOnly()
        }
    }

    func performSpaceRefreshOnly() async {
        logDebug("Performing space-only refresh...")
        let result = await performSpaceRefresh()

        await MainActor.run {
            if case .success(let (displays, spaces)) = result {
                self.spaceModel.displays = displays
                self.spaceModel.spaces = spaces
                self.spaceModel.errorMessage = nil
                logDebug(
                    "Space-only refresh completed: \(displays.count) displays, \(spaces.count) spaces"
                )
            } else if case .failure(let error) = result {
                self.spaceModel.errorMessage = "Failed to load space information"
                logError("Space-only refresh failed: \(error)")
            }
        }
    }

    func updateWindows(_ windows: [Window]) {
        DispatchQueue.main.async { [weak self] in
            self?.spaceModel.windows = windows
            self?.spaceModel.errorMessage = nil
            logDebug("Windows updated: \(windows.count) windows")
        }
    }

    func setErrorMessage(_ message: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.spaceModel.errorMessage = message
            if let msg = message {
                logWarning("Error message set: \(msg)")
            }
        }
    }

    deinit {
        logDebug("DataRefreshManager deinit - cancelling pending tasks")
        // Ensure any in-flight refresh is cancelled to avoid background work retaining resources
        currentTask?.cancel()
        currentTask = nil
    }
}
