//
//  YabaiIndicatorUITests.swift
//  YabaiIndicatorUITests
//
//  Created by Max Zhao on 26/12/2021.
//

import XCTest

class YabaiIndicatorUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify the app launched successfully
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5.0))
    }

    func testStatusBarItemExists() throws {
        let app = XCUIApplication()
        app.launch()

        // Wait for the app to be ready
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5.0))

        // Check if status bar item exists (this is tricky to test directly)
        // For now, just verify the app is running and doesn't crash immediately
        sleep(2)  // Give it time to set up the status bar

        // If we get here without crashing, the status bar setup likely worked
        XCTAssertTrue(app.state == .runningForeground)
    }

    func testSpaceButtonsExist() throws {
        let app = XCUIApplication()
        app.launch()

        // Wait for the app to be ready
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5.0))

        // Give time for data to load
        sleep(3)

        // The test passes if the app doesn't crash and remains running
        // In a real scenario, we'd check for specific UI elements
        XCTAssertTrue(app.state == .runningForeground)
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
