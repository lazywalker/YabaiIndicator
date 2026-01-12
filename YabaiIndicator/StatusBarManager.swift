//
//  StatusBarManager.swift
//  YabaiIndicator
//
//  Created for architecture refactoring
//

import Combine
import SwiftUI

class StatusBarManager {
    private var statusBarItem: NSStatusItem?
    private var spaceModel: SpaceModel
    private var sinks: [AnyCancellable] = []
    private var hostingView: NSHostingView<AnyView>?
    private var refreshCount: Int = 0

    init(spaceModel: SpaceModel) {
        self.spaceModel = spaceModel
        logDebug("StatusBarManager initialized")
    }

    func setupStatusBar() {
        logDebug("Setting up status bar...")
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem?.menu = createMenu()
        refreshButtonStyle()
        setupObservers()
        logInfo("Status bar setup completed")
    }

    private func setupObservers() {
        logDebug("Setting up status bar observers...")
        sinks = [
            spaceModel.objectWillChange
                .receive(on: DispatchQueue.main)  // Ensure main thread
                .sink { [weak self] _ in
                    self?.refreshBar()
                },
            UserDefaults.standard.publisher(for: \.showDisplaySeparator)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.refreshBar()
                },
            UserDefaults.standard.publisher(for: \.showCurrentSpaceOnly)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.refreshBar()
                },
            UserDefaults.standard.publisher(for: \.buttonStyle)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.refreshButtonStyle()
                },
        ]
        logDebug("Status bar observers configured: \(sinks.count) subscriptions")
    }

    private func refreshBar() {
        // Ensure we're on main thread for UI updates
        guard Thread.isMainThread else {
            logWarning("refreshBar called from background thread, dispatching to main")
            DispatchQueue.main.async { [weak self] in
                self?.refreshBar()
            }
            return
        }

        refreshCount += 1

        let showDisplaySeparator = UserDefaults.standard.bool(forKey: "showDisplaySeparator")
        let showCurrentSpaceOnly = UserDefaults.standard.bool(forKey: "showCurrentSpaceOnly")

        let numButtons = showCurrentSpaceOnly ? spaceModel.displays.count : spaceModel.spaces.count

        var newWidth = CGFloat(numButtons) * Constants.itemWidth
        if !showDisplaySeparator {
            newWidth -= CGFloat((spaceModel.displays.count - 1) * 10)
        }

        // Safety check for valid width
        if newWidth < 0 || !newWidth.isFinite {
            logWarning("Invalid width calculated: \(newWidth), using default")
            newWidth = Constants.itemWidth
        }

        statusBarItem?.button?.frame.size.width = newWidth
        if let firstSubview = statusBarItem?.button?.subviews.first {
            firstSubview.frame.size.width = newWidth
        }

        // Log every 100th refresh to avoid log spam
        if refreshCount % 100 == 0 {
            logDebug("StatusBar refreshed \(refreshCount) times total")
        }
    }

    private func refreshButtonStyle() {
        // Ensure we're on main thread for UI updates
        guard Thread.isMainThread else {
            logWarning("refreshButtonStyle called from background thread, dispatching to main")
            DispatchQueue.main.async { [weak self] in
                self?.refreshButtonStyle()
            }
            return
        }

        logDebug("Refreshing button style...")

        // Calculate the correct width before creating new view
        let showDisplaySeparator = UserDefaults.standard.bool(forKey: "showDisplaySeparator")
        let showCurrentSpaceOnly = UserDefaults.standard.bool(forKey: "showCurrentSpaceOnly")
        let numButtons = showCurrentSpaceOnly ? spaceModel.displays.count : spaceModel.spaces.count
        var newWidth = CGFloat(numButtons) * Constants.itemWidth
        if !showDisplaySeparator {
            newWidth -= CGFloat((spaceModel.displays.count - 1) * 10)
        }

        // Safety check for valid width
        if newWidth < 0 || !newWidth.isFinite {
            logWarning("Invalid width in refreshButtonStyle: \(newWidth), using default")
            newWidth = Constants.itemWidth
        }

        // Remove existing subviews
        for subView in statusBarItem?.button?.subviews ?? [] {
            subView.removeFromSuperview()
        }

        // Create or reuse hosting view
        if hostingView == nil {
            hostingView = NSHostingView(
                rootView: AnyView(ContentView().environmentObject(spaceModel)))
            logDebug("Created new hosting view")
        }

        hostingView?.setFrameSize(NSSize(width: newWidth, height: Constants.statusBarHeight))
        if let hostingView = hostingView {
            statusBarItem?.button?.addSubview(hostingView)
        }

        // Update button frame
        statusBarItem?.button?.frame.size.width = newWidth
        logDebug("Button style refreshed, width: \(newWidth)")
    }

    private func createStatusItemView() -> NSView {
        let view = NSHostingView(
            rootView: ContentView().environmentObject(spaceModel)
        )
        view.setFrameSize(NSSize(width: 0, height: Constants.statusBarHeight))
        return view
    }

    private func createMenu() -> NSMenu {
        let statusBarMenu = NSMenu()

        let preferencesItem = NSMenuItem(
            title: "Preferences",
            action: #selector(openPreferences),
            keyEquivalent: ""
        )
        preferencesItem.target = self
        statusBarMenu.addItem(preferencesItem)

        statusBarMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: ""
        )
        quitItem.target = self
        statusBarMenu.addItem(quitItem)

        return statusBarMenu
    }

    @objc private func openPreferences() {
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        logInfo("User requested quit")
        NSApp.terminate(self)
    }

    deinit {
        logDebug("StatusBarManager deinit starting...")

        // Cancel all Combine subscriptions
        sinks.forEach { $0.cancel() }
        sinks.removeAll()

        // Clean up hosting view on main thread
        if Thread.isMainThread {
            hostingView?.removeFromSuperview()
            hostingView = nil
            if let item = statusBarItem {
                NSStatusBar.system.removeStatusItem(item)
            }
        } else {
            let view = hostingView
            let item = statusBarItem
            DispatchQueue.main.sync {
                view?.removeFromSuperview()
                if let item = item {
                    NSStatusBar.system.removeStatusItem(item)
                }
            }
            hostingView = nil
        }

        logDebug("StatusBarManager deinit completed")
    }
}
