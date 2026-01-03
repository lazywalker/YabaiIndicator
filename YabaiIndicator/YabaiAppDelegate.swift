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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load default preferences
        if let prefs = Bundle.main.path(forResource: "defaults", ofType: "plist"),
            let dict = NSDictionary(contentsOfFile: prefs) as? [String: Any]
        {
            UserDefaults.standard.register(defaults: dict)
        }

        // Setup status bar
        statusBarManager.setupStatusBar()

        // Register workspace observers
        registerObservers()

        // Start socket server
        socketTask = Task {
            await socketServer.start()
        }

        // Initial data refresh
        dataRefreshManager.refreshData()
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketTask?.cancel()
        socketServer.stop()
    }

    private func registerObservers() {
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

        // Add observer for manual refresh requests
        NotificationCenter.default.addObserver(
            dataRefreshManager,
            selector: #selector(DataRefreshManager.refreshData),
            name: NSNotification.Name("RefreshData"),
            object: nil
        )
    }
}
