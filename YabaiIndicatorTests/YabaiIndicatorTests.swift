//
//  YabaiIndicatorTests.swift
//  YabaiIndicatorTests
//
//  Created by Max Zhao on 26/12/2021.
//

import XCTest
@testable import YabaiIndicator

class YabaiIndicatorTests: XCTestCase {

    var nativeClient: NativeClient!
    
    override func setUpWithError() throws {
        nativeClient = NativeClient()
    }

    override func tearDownWithError() throws {
        nativeClient = nil
    }

    func testQuerySpacesSuccess() throws {
        // Test that querySpaces returns a non-empty array when successful
        do {
            let spaces = try nativeClient.querySpaces()
            XCTAssertFalse(spaces.isEmpty, "Spaces array should not be empty")
            
            // Verify space properties
            for space in spaces {
                XCTAssertGreaterThan(space.spaceid, 0, "Space ID should be greater than 0")
                XCTAssertFalse(space.uuid.isEmpty, "Space UUID should not be empty")
                XCTAssertGreaterThanOrEqual(space.display, 1, "Display index should be >= 1")
                XCTAssertGreaterThanOrEqual(space.index, 1, "Space index should be >= 1")
            }
        } catch {
            // If yabai is not running, this is expected
            if case NativeClientError.connectionFailed = error {
                print("Skipping test: yabai not available")
                throw XCTSkip("yabai not running")
            }
            throw error
        }
    }
    
    func testQueryDisplaysSuccess() throws {
        // Test that queryDisplays returns a non-empty array when successful
        do {
            let displays = try nativeClient.queryDisplays()
            XCTAssertFalse(displays.isEmpty, "Displays array should not be empty")
            
            // Verify display properties
            for display in displays {
                XCTAssertGreaterThan(display.id, 0, "Display ID should be greater than 0")
                XCTAssertFalse(display.uuid.isEmpty, "Display UUID should not be empty")
                XCTAssertGreaterThanOrEqual(display.index, 0, "Display index should be >= 0")
                XCTAssertGreaterThan(display.frame.width, 0, "Display width should be > 0")
                XCTAssertGreaterThan(display.frame.height, 0, "Display height should be > 0")
            }
        } catch {
            // If system APIs fail, this is expected in some environments
            if case NativeClientError.displayQueryFailed = error {
                print("Skipping test: display query failed")
                throw XCTSkip("Display query failed")
            }
            throw error
        }
    }

    func testYabaiClientQueryWindows() throws {
        // Test that queryWindows works when yabai is available
        do {
            let windows = try gYabaiClient.queryWindows()
            // Windows array can be empty, that's fine
            for window in windows {
                XCTAssertGreaterThan(window.id, 0, "Window ID should be greater than 0")
                XCTAssertGreaterThanOrEqual(window.pid, 0, "PID should be >= 0")
                XCTAssertFalse(window.app.isEmpty, "App name should not be empty")
                XCTAssertGreaterThan(window.frame.width, 0, "Window width should be > 0")
                XCTAssertGreaterThan(window.frame.height, 0, "Window height should be > 0")
            }
        } catch {
            // If yabai is not running, this is expected
            if case YabaiClientError.yabaiCommandFailed = error {
                print("Skipping test: yabai not running")
                throw XCTSkip("yabai not running")
            }
            throw error
        }
    }
    
    func testDataRefreshManager() throws {
        let spaceModel = SpaceModel()
        let dataRefreshManager = DataRefreshManager(spaceModel: spaceModel)
        
        // Test initial state
        XCTAssertTrue(spaceModel.spaces.isEmpty)
        XCTAssertTrue(spaceModel.displays.isEmpty)
        XCTAssertTrue(spaceModel.windows.isEmpty)
        XCTAssertNil(spaceModel.errorMessage)
        
        // Test refresh (this will run asynchronously)
        dataRefreshManager.refreshData()
        
        // Wait a bit for async operation
        let expectation = XCTestExpectation(description: "Data refresh completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Check that either data was loaded or an error was set
            if spaceModel.spaces.isEmpty && spaceModel.errorMessage == nil {
                // Still loading, wait a bit more
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    expectation.fulfill()
                }
            } else {
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
        
        // Verify that either spaces were loaded or an error message was set
        XCTAssertTrue(!spaceModel.spaces.isEmpty || spaceModel.errorMessage != nil)
    }

    func testDataRefreshManagerDeinit() {
        weak var weakRef: DataRefreshManager?
        autoreleasepool {
            var mgr: DataRefreshManager? = DataRefreshManager(spaceModel: SpaceModel())
            weakRef = mgr
            mgr?.refreshData()
            mgr = nil
        }
        // Give the run loop a moment to run cleanup
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertNil(weakRef, "DataRefreshManager should be deallocated and not leak")
    }

    func testStatusBarManagerDeinit() {
        weak var weakRef: StatusBarManager?
        autoreleasepool {
            var mgr: StatusBarManager? = StatusBarManager(spaceModel: SpaceModel())
            weakRef = mgr
            mgr = nil
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertNil(weakRef, "StatusBarManager should be deallocated and not leak")
    }
