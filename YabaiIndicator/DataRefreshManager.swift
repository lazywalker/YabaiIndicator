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

    init(spaceModel: SpaceModel) {
        self.spaceModel = spaceModel
    }

    @objc func refreshData() {
        // Debounce rapid refresh calls to prevent excessive updates
        let now = Date()
        guard now.timeIntervalSince(lastRefreshTime) > 0.1 else { return }
        lastRefreshTime = now

        // Cancel any pending refresh task to prevent overlapping requests
        currentTask?.cancel()
        currentTask = nil

        // Store the task so it can be cancelled if the manager is deallocated
        currentTask = Task { [weak self] in
            await self?.performAsyncRefresh()
            // Clear reference when done
            Task { @MainActor in self?.currentTask = nil }
        }
    }

    func performAsyncRefresh() async {
        // Perform both space and window refresh concurrently
        async let spaceRefresh = performSpaceRefresh()
        async let windowRefresh = performWindowRefresh()

        // Wait for both to complete
        let (spaceResult, windowResult) = await (spaceRefresh, windowRefresh)

        // Update UI on main thread
        await MainActor.run {
            if case .success(let (displays, spaces)) = spaceResult {
                self.spaceModel.displays = displays
                self.spaceModel.spaces = spaces
            }

            if case .success(let windows) = windowResult {
                self.spaceModel.windows = windows
            }

            // Set error message if both failed
            if case .failure = spaceResult, case .failure = windowResult {
                self.spaceModel.errorMessage = "Failed to load space and window information"
            } else if case .failure = spaceResult {
                self.spaceModel.errorMessage = "Failed to load space information"
            } else if case .failure = windowResult {
                self.spaceModel.errorMessage = "Failed to load window information"
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

            return .success((displays: displays, spaces: spaces))
        } catch {
            print("DataRefreshManager: Failed to refresh space data - \(error)")
            return .failure(error)
        }
    }

    func performWindowRefresh() async -> Result<[Window], Error> {
        guard UserDefaults.standard.buttonStyle == .windows else {
            return .success([])
        }

        do {
            let windows = try await Task { try gYabaiClient.queryWindows() }.value
            return .success(windows)
        } catch {
            print("DataRefreshManager: Failed to refresh window data - \(error)")
            return .failure(error)
        }
    }

    @objc func onSpaceChanged(_ notification: Notification) {
        Task { [weak self] in
            await self?.performSpaceRefreshOnly()
        }
    }

    @objc func onDisplayChanged(_ notification: Notification) {
        Task { [weak self] in
            await self?.performSpaceRefreshOnly()
        }
    }

    func performSpaceRefreshOnly() async {
        let result = await performSpaceRefresh()

        await MainActor.run {
            if case .success(let (displays, spaces)) = result {
                self.spaceModel.displays = displays
                self.spaceModel.spaces = spaces
                self.spaceModel.errorMessage = nil
            } else if case .failure = result {
                self.spaceModel.errorMessage = "Failed to load space information"
            }
        }
    }

    func updateWindows(_ windows: [Window]) {
        DispatchQueue.main.async { [weak self] in
            self?.spaceModel.windows = windows
            self?.spaceModel.errorMessage = nil
        }
    }

    func setErrorMessage(_ message: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.spaceModel.errorMessage = message
        }
    }

    deinit {
        // Ensure any in-flight refresh is cancelled to avoid background work retaining resources
        currentTask?.cancel()
        currentTask = nil
    }
}
