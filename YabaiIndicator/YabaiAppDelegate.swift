//
//  YabaiAppDelegate.swift
//  YabaiIndicator
//
//  Created by Max Zhao on 26/12/2021.
//

import Combine
import SwiftUI

extension UserDefaults {
    @objc dynamic var showDisplaySeparator: Bool {
        return bool(forKey: "showDisplaySeparator")
    }

    @objc dynamic var showCurrentSpaceOnly: Bool {
        return bool(forKey: "showCurrentSpaceOnly")
    }

    @objc dynamic var buttonStyle: ButtonStyle {
        return ButtonStyle(rawValue: self.integer(forKey: "buttonStyle")) ?? ButtonStyle.numeric
    }
}

class YabaiAppDelegate: NSObject, NSApplicationDelegate {
    private let spaceModel = SpaceModel()
    private lazy var statusBarManager = StatusBarManager(spaceModel: spaceModel)
    private lazy var dataRefreshManager = DataRefreshManager(spaceModel: spaceModel)
    private lazy var socketServer = SocketServer(dataRefreshManager: dataRefreshManager)

    private var socketTask: Task<Void, Never>?
    private var observersRegistered = false
    private var refreshTimer: Timer?
    private var memoryWarningObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize logger first
        _ = Logger.shared
        logInfo("Application launching...")

        // Load default preferences
        if let prefs = Bundle.main.path(forResource: "defaults", ofType: "plist"),
            let dict = NSDictionary(contentsOfFile: prefs) as? [String: Any]
        {
            UserDefaults.standard.register(defaults: dict)
            logDebug("Loaded default preferences")
        }

        // Setup status bar
        statusBarManager.setupStatusBar()
        logInfo("Status bar initialized")

        // Register workspace observers
        registerObservers()

        // Start socket server
        socketTask = Task {
            await socketServer.start()
        }
        logInfo("Socket server task started")

        // Initial data refresh
        dataRefreshManager.refreshData()

        // Setup periodic refresh to handle missed events
        setupPeriodicRefresh()

        // Setup memory warning observer
        setupMemoryWarningObserver()

        logInfo("Application launch completed successfully")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logInfo("Application terminating...")
        Logger.shared.logStats()

        socketTask?.cancel()
        socketServer.stop()

        logInfo("Application terminated gracefully")
        Logger.shared.flush()
    }

    private func registerObservers() {
        guard !observersRegistered else {
            logWarning("Observers already registered, skipping")
            return
        }
        observersRegistered = true
        logDebug("Registering workspace observers...")

        NSWorkspace.shared.notificationCenter.addObserver(
            dataRefreshManager,
            selector: #selector(DataRefreshManager.onSpaceChanged(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            dataRefreshManager,
            selector: #selector(DataRefreshManager.onDisplayChanged(_:)),
            name: Notification.Name("NSWorkspaceActiveDisplayDidChangeNotification"),
            object: nil
        )

        // Add observer for window focus change to catch moved windows
        NSWorkspace.shared.notificationCenter.addObserver(
            dataRefreshManager,
            selector: #selector(DataRefreshManager.onSpaceChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Add observer for manual refresh requests
        NotificationCenter.default.addObserver(
            dataRefreshManager,
            selector: #selector(DataRefreshManager.refreshData),
            name: NSNotification.Name("RefreshData"),
            object: nil
        )

        logInfo("Workspace observers registered successfully")
    }

    private func setupPeriodicRefresh() {
        // Setup a fallback periodic refresh timer to catch events that might be missed
        // This helps recover from any event handling issues
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.dataRefreshManager.refreshData()
        }
        logDebug("Periodic refresh timer started (interval: 2.0s)")
    }

    private func setupMemoryWarningObserver() {
        // Log periodic stats every hour
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard self != nil else { return }
            logInfo("Hourly stats checkpoint")
            Logger.shared.logStats()
        }
        logDebug("Memory and stats monitoring started")
    }

    deinit {
        logDebug("YabaiAppDelegate deinit starting...")

        // Cancel timer
        refreshTimer?.invalidate()
        refreshTimer = nil

        // Remove all notification observers
        if observersRegistered {
            NotificationCenter.default.removeObserver(dataRefreshManager)
            NSWorkspace.shared.notificationCenter.removeObserver(dataRefreshManager)
            observersRegistered = false
        }

        // Remove memory warning observer
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        // Cancel socket task
        socketTask?.cancel()
        socketTask = nil

        logDebug("YabaiAppDelegate deinit completed")
    }
}
