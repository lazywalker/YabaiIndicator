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

    init(spaceModel: SpaceModel) {
        self.spaceModel = spaceModel
    }

    func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem?.menu = createMenu()
        refreshButtonStyle()
        setupObservers()
    }

    private func setupObservers() {
        sinks = [
            spaceModel.objectWillChange.sink { [weak self] _ in
                self?.refreshBar()
            },
            UserDefaults.standard.publisher(for: \.showDisplaySeparator).sink { [weak self] _ in
                self?.refreshBar()
            },
            UserDefaults.standard.publisher(for: \.showCurrentSpaceOnly).sink { [weak self] _ in
                self?.refreshBar()
            },
            UserDefaults.standard.publisher(for: \.buttonStyle).sink { [weak self] _ in
                self?.refreshButtonStyle()
            },
        ]
    }

    private func refreshBar() {
        let showDisplaySeparator = UserDefaults.standard.bool(forKey: "showDisplaySeparator")
        let showCurrentSpaceOnly = UserDefaults.standard.bool(forKey: "showCurrentSpaceOnly")

        let numButtons = showCurrentSpaceOnly ? spaceModel.displays.count : spaceModel.spaces.count

        var newWidth = CGFloat(numButtons) * Constants.itemWidth
        if !showDisplaySeparator {
            newWidth -= CGFloat((spaceModel.displays.count - 1) * 10)
        }
        statusBarItem?.button?.frame.size.width = newWidth
        statusBarItem?.button?.subviews[0].frame.size.width = newWidth
    }

    private func refreshButtonStyle() {
        // Calculate the correct width before creating new view
        let showDisplaySeparator = UserDefaults.standard.bool(forKey: "showDisplaySeparator")
        let showCurrentSpaceOnly = UserDefaults.standard.bool(forKey: "showCurrentSpaceOnly")
        let numButtons = showCurrentSpaceOnly ? spaceModel.displays.count : spaceModel.spaces.count
        var newWidth = CGFloat(numButtons) * Constants.itemWidth
        if !showDisplaySeparator {
            newWidth -= CGFloat((spaceModel.displays.count - 1) * 10)
        }

        // Remove existing subviews
        for subView in statusBarItem?.button?.subviews ?? [] {
            subView.removeFromSuperview()
        }

        // Add new view with correct width
        let newView = createStatusItemView()
        newView.setFrameSize(NSSize(width: newWidth, height: Constants.statusBarHeight))
        statusBarItem?.button?.addSubview(newView)

        // Update button frame
        statusBarItem?.button?.frame.size.width = newWidth
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
        NSApp.terminate(self)
    }

    deinit {
        sinks.forEach { $0.cancel() }
        sinks.removeAll()
        if let item = statusBarItem {
            NSStatusBar.system.removeStatusItem(item)
        }
    }
}
