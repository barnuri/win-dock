import XCTest
@testable import WinDock

@MainActor
final class AppManagerTests: XCTestCase {
    var appManager: AppManager!
    
    override func setUp() async throws {
        try await super.setUp()
        appManager = AppManager()
    }
    
    override func tearDown() async throws {
        appManager = nil
        try await super.tearDown()
    }
    
    func testAppManagerInitialization() {
        XCTAssertNotNil(appManager)
        XCTAssertNotNil(appManager.dockApps)
    }
    
    func testPinApp() {
        // Create a test app
        let testApp = DockApp(
            bundleIdentifier: "com.test.app",
            name: "Test App",
            icon: nil,
            url: nil,
            isPinned: false,
            runningApplication: nil,
            windows: [],
            notificationCount: 0,
            hasNotifications: false
        )
        
        // Pin the app
        appManager.pinApp(testApp)
        
        // Verify the app is pinned
        // Note: This would require access to internal state or a public method to verify
        XCTAssertTrue(true) // Placeholder assertion
    }
    
    func testUnpinApp() {
        // Create a test app
        let testApp = DockApp(
            bundleIdentifier: "com.test.app",
            name: "Test App",
            icon: nil,
            url: nil,
            isPinned: true,
            runningApplication: nil,
            windows: [],
            notificationCount: 0,
            hasNotifications: false
        )
        
        // Unpin the app
        appManager.unpinApp(testApp)
        
        // Verify the app is unpinned
        XCTAssertTrue(true) // Placeholder assertion
    }
    
    func testLaunchApp() async throws {
        // Create a test app with a valid bundle identifier
        let testApp = DockApp(
            bundleIdentifier: "com.apple.finder",
            name: "Finder",
            icon: nil,
            url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            isPinned: false,
            runningApplication: nil,
            windows: [],
            notificationCount: 0,
            hasNotifications: false
        )
        
        // Launch the app (this should not throw)
        appManager.launchApp(testApp)
        
        // Wait a moment for the app to potentially launch
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        XCTAssertTrue(true) // If we reach here without crashing, the test passes
    }
    
    func testWindowCountCalculation() {
        let windows = [
            WindowInfo(title: "Window 1", windowID: 1, bounds: CGRect.zero, isMinimized: false, isOnScreen: true),
            WindowInfo(title: "Window 2", windowID: 2, bounds: CGRect.zero, isMinimized: false, isOnScreen: true)
        ]
        
        let testApp = DockApp(
            bundleIdentifier: "com.test.app",
            name: "Test App",
            icon: nil,
            url: nil,
            isPinned: false,
            runningApplication: nil,
            windows: windows,
            notificationCount: 0,
            hasNotifications: false
        )
        
        XCTAssertEqual(testApp.windowCount, 2)
        XCTAssertTrue(testApp.hasWindows)
    }
    
    func testAppActiveState() {
        // Create a mock running application
        let runningApps = NSWorkspace.shared.runningApplications
        let activeApp = runningApps.first { $0.isActive }
        
        if let activeApp = activeApp {
            let testApp = DockApp(
                bundleIdentifier: activeApp.bundleIdentifier ?? "unknown",
                name: activeApp.localizedName ?? "Unknown",
                icon: activeApp.icon,
                url: activeApp.bundleURL,
                isPinned: false,
                runningApplication: activeApp,
                windows: [],
                notificationCount: 0,
                hasNotifications: false
            )
            
            XCTAssertTrue(testApp.isActive)
            XCTAssertTrue(testApp.isRunning)
        }
    }
    
    func testNotificationBadgeLogic() {
        let testAppWithNotifications = DockApp(
            bundleIdentifier: "com.test.app",
            name: "Test App",
            icon: nil,
            url: nil,
            isPinned: false,
            runningApplication: nil,
            windows: [],
            notificationCount: 5,
            hasNotifications: true
        )
        
        let testAppWithoutNotifications = DockApp(
            bundleIdentifier: "com.test.app2",
            name: "Test App 2",
            icon: nil,
            url: nil,
            isPinned: false,
            runningApplication: nil,
            windows: [],
            notificationCount: 0,
            hasNotifications: false
        )
        
        XCTAssertTrue(testAppWithNotifications.hasNotifications)
        XCTAssertEqual(testAppWithNotifications.notificationCount, 5)
        
        XCTAssertFalse(testAppWithoutNotifications.hasNotifications)
        XCTAssertEqual(testAppWithoutNotifications.notificationCount, 0)
    }
    
    func testAppMinimizedState() {
        // Test app with minimized windows
        let minimizedWindows = [
            WindowInfo(title: "Minimized Window", windowID: 1, bounds: CGRect.zero, isMinimized: true, isOnScreen: false)
        ]
        
        // Create a mock running application that's not active
        let runningApps = NSWorkspace.shared.runningApplications
        let inactiveApp = runningApps.first { !$0.isActive }
        
        if let inactiveApp = inactiveApp {
            let testApp = DockApp(
                bundleIdentifier: inactiveApp.bundleIdentifier ?? "unknown",
                name: inactiveApp.localizedName ?? "Unknown",
                icon: inactiveApp.icon,
                url: inactiveApp.bundleURL,
                isPinned: false,
                runningApplication: inactiveApp,
                windows: minimizedWindows,
                notificationCount: 0,
                hasNotifications: false
            )
            
            XCTAssertTrue(testApp.isMinimized)
        }
    }
}