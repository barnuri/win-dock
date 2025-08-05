import ApplicationServices
import Cocoa
import os.log

enum NotificationPosition: String, CaseIterable {
    case topLeft, topMiddle, topRight
    case middleLeft, deadCenter, middleRight
    case bottomLeft, bottomMiddle, bottomRight

    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topMiddle: return "Top Middle"
        case .topRight: return "Top Right"
        case .middleLeft: return "Middle Left"
        case .deadCenter: return "Middle"
        case .middleRight: return "Middle Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomMiddle: return "Bottom Middle"
        case .bottomRight: return "Bottom Right"
        }
    }
}

class NotificationPositionManager: NSObject, ObservableObject {
    static let shared = NotificationPositionManager()
    
    @Published var isEnabled: Bool = false
    @Published var currentPosition: NotificationPosition = .topRight
    @Published var lastError: String?
    @Published var isProcessing: Bool = false
    
    private let notificationCenterBundleID: String = "com.apple.notificationcenterui"
    private let paddingAboveDock: CGFloat = 30
    private var axObserver: AXObserver?
    private let logger: Logger = .init(subsystem: "com.windock.NotificationPositionManager", category: "NotificationPositionManager")
    
    private var cachedInitialPosition: CGPoint?
    private var cachedInitialWindowSize: CGSize?
    private var cachedInitialNotifSize: CGSize?
    private var cachedInitialPadding: CGFloat?
    
    private var widgetMonitorTimer: Timer?
    private var lastWidgetWindowCount: Int = 0
    private var pollingEndTime: Date?
    
    override init() {
        super.init()
        loadSettings()
        if isEnabled {
            setupObserver()
        }
    }
    
    private func loadSettings() {
        isEnabled = UserDefaults.standard.bool(forKey: "notificationPositionEnabled")
        
        if let rawValue = UserDefaults.standard.string(forKey: "notificationPosition"),
           let position = NotificationPosition(rawValue: rawValue) {
            currentPosition = position
        } else {
            currentPosition = .topRight
        }
    }
    
    func updateSettings(enabled: Bool, position: NotificationPosition) {
        isEnabled = enabled
        currentPosition = position
        
        UserDefaults.standard.set(enabled, forKey: "notificationPositionEnabled")
        UserDefaults.standard.set(position.rawValue, forKey: "notificationPosition")
        
        if enabled {
            setupObserver()
        } else {
            stopObserver()
        }
        
        AppLogger.shared.info("Notification position settings updated: enabled=\(enabled), position=\(position.displayName)")
    }
    
    private func debugLog(_ message: String) {
        logger.info("\(message, privacy: .public)")
        AppLogger.shared.debug("NotificationPositionManager: \(message)")
    }
    
    private func setupObserver() {
        guard isEnabled else { return }
        
        guard checkAccessibilityPermissions() else {
            lastError = "Accessibility permissions not granted"
            return
        }
        
        guard let pid = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == notificationCenterBundleID
        })?.processIdentifier else {
            lastError = "Notification Center not found"
            debugLog("Failed to setup observer - Notification Center not found")
            return
        }

        let app: AXUIElement = AXUIElementCreateApplication(pid)
        var observer: AXObserver?
        
        let result = AXObserverCreate(pid, observerCallback, &observer)
        guard result == .success, let observer = observer else {
            lastError = "Failed to create accessibility observer"
            debugLog("Failed to create observer: \(result)")
            return
        }
        
        axObserver = observer

        let selfPtr: UnsafeMutableRawPointer = Unmanaged.passUnretained(self).toOpaque()
        let addNotificationResult = AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, selfPtr)
        
        guard addNotificationResult == .success else {
            lastError = "Failed to add window creation notification"
            debugLog("Failed to add notification: \(addNotificationResult)")
            return
        }
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        
        lastError = nil
        debugLog("Observer setup complete for Notification Center (PID: \(pid))")

        widgetMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            self.checkForWidgetChanges()
        }
        
        // Move any existing notifications
        moveAllNotifications()
    }
    
    private func stopObserver() {
        axObserver = nil
        widgetMonitorTimer?.invalidate()
        widgetMonitorTimer = nil
        cachedInitialPosition = nil
        cachedInitialWindowSize = nil
        cachedInitialNotifSize = nil
        cachedInitialPadding = nil
        debugLog("Observer stopped and caches cleared")
    }
    
    func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func moveNotification(_ window: AXUIElement) {
        guard isEnabled else { return }
        guard currentPosition != .topRight else { return } // Default position, no need to move

        if hasNotificationCenterUI() {
            debugLog("Skipping move - Notification Center UI detected")
            return
        }

        let targetSubroles: [String] = ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]
        guard let windowSize: CGSize = getSize(of: window),
              let bannerContainer: AXUIElement = findElementWithSubrole(root: window, targetSubroles: targetSubroles),
              let notifSize: CGSize = getSize(of: bannerContainer),
              let position: CGPoint = getPosition(of: bannerContainer)
        else {
            debugLog("Failed to get notification dimensions or find banner container")
            return
        }

        if cachedInitialPosition == nil {
            cacheInitialNotificationData(windowSize: windowSize, notifSize: notifSize, position: position)
        } else if position != cachedInitialPosition {
            setPosition(window, x: cachedInitialPosition!.x, y: cachedInitialPosition!.y)
        }

        let newPosition: (x: CGFloat, y: CGFloat) = calculateNewPosition(
            windowSize: cachedInitialWindowSize!,
            notifSize: cachedInitialNotifSize!,
            position: cachedInitialPosition!,
            padding: cachedInitialPadding!
        )

        setPosition(window, x: newPosition.x, y: newPosition.y)

        pollingEndTime = Date().addingTimeInterval(6.5)
        debugLog("Moved notification to \(currentPosition.displayName) at (\(newPosition.x), \(newPosition.y))")
    }
    
    private func moveAllNotifications() {
        guard isEnabled else { return }
        
        guard let pid = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == notificationCenterBundleID
        })?.processIdentifier else {
            debugLog("Cannot find Notification Center process")
            return
        }

        let app: AXUIElement = AXUIElementCreateApplication(pid)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows: [AXUIElement] = windowsRef as? [AXUIElement]
        else {
            debugLog("Failed to get notification windows")
            return
        }

        for window in windows {
            moveNotification(window)
        }
    }
    
    private func cacheInitialNotificationData(windowSize: CGSize, notifSize: CGSize, position: CGPoint) {
        guard cachedInitialPosition == nil else { return }

        let screenWidth: CGFloat = NSScreen.main!.frame.width
        var padding: CGFloat
        var effectivePosition = position

        if position.x + notifSize.width > screenWidth {
            debugLog("Detected incorrect initial position.x: \(position.x). Recalculating position.")
            padding = 16.0
            effectivePosition.x = screenWidth - notifSize.width - padding
        } else {
            let rightEdge: CGFloat = position.x + notifSize.width
            padding = screenWidth - rightEdge
        }

        cachedInitialPosition = effectivePosition
        cachedInitialWindowSize = windowSize
        cachedInitialNotifSize = notifSize
        cachedInitialPadding = padding

        debugLog("Initial notification cached - size: \(notifSize), position: \(effectivePosition), padding: \(padding)")
    }
    
    private func calculateNewPosition(
        windowSize: CGSize,
        notifSize: CGSize,
        position: CGPoint,
        padding: CGFloat
    ) -> (x: CGFloat, y: CGFloat) {
        debugLog("Calculating new position with windowSize: \(windowSize), notifSize: \(notifSize), position: \(position), padding: \(padding)")
        let newX: CGFloat
        let newY: CGFloat

        switch currentPosition {
        case .topLeft, .middleLeft, .bottomLeft:
            newX = padding - position.x
        case .topMiddle, .bottomMiddle, .deadCenter:
            newX = (windowSize.width - notifSize.width) / 2 - position.x
        case .topRight, .middleRight, .bottomRight:
            newX = 0
        }

        switch currentPosition {
        case .topLeft, .topMiddle, .topRight:
            newY = 0
        case .middleLeft, .middleRight, .deadCenter:
            let dockSize: CGFloat = NSScreen.main!.frame.height - NSScreen.main!.visibleFrame.height
            newY = (windowSize.height - notifSize.height) / 2 - dockSize
        case .bottomLeft, .bottomMiddle, .bottomRight:
            let dockSize: CGFloat = NSScreen.main!.frame.height - NSScreen.main!.visibleFrame.height
            newY = windowSize.height - notifSize.height - dockSize - paddingAboveDock
        }

        debugLog("Calculated new position - x: \(newX), y: \(newY)")
        return (newX, newY)
    }
    
    private func checkForWidgetChanges() {
        guard let pollingEnd = pollingEndTime, Date() < pollingEnd else {
            return
        }

        let hasNCUI: Bool = hasNotificationCenterUI()
        let currentNCState: Int = hasNCUI ? 1 : 0

        if lastWidgetWindowCount != currentNCState {
            debugLog("Notification Center state changed (\(lastWidgetWindowCount) → \(currentNCState)) - triggering move")
            if !hasNCUI {
                moveAllNotifications()
            }
        }

        lastWidgetWindowCount = currentNCState
    }

    private func hasNotificationCenterUI() -> Bool {
        guard let pid = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == notificationCenterBundleID
        })?.processIdentifier else { return false }

        let app: AXUIElement = AXUIElementCreateApplication(pid)
        return findElementWithWidgetIdentifier(root: app) != nil
    }

    private func findElementWithWidgetIdentifier(root: AXUIElement) -> AXUIElement? {
        if let identifier: String = getWindowIdentifier(root), identifier.hasPrefix("widget-local") {
            return root
        }

        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children: [AXUIElement] = childrenRef as? [AXUIElement] else { return nil }

        for child: AXUIElement in children {
            if let found: AXUIElement = findElementWithWidgetIdentifier(root: child) {
                return found
            }
        }
        return nil
    }
    
    private func getWindowIdentifier(_ element: AXUIElement) -> String? {
        var identifierRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierRef) == .success else {
            return nil
        }
        return identifierRef as? String
    }

    private func getPosition(of element: AXUIElement) -> CGPoint? {
        var positionValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        guard let posVal: AnyObject = positionValue, AXValueGetType(posVal as! AXValue) == .cgPoint else {
            return nil
        }
        var position = CGPoint.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
        return position
    }

    private func getSize(of element: AXUIElement) -> CGSize? {
        var sizeValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        guard let sizeVal: AnyObject = sizeValue, AXValueGetType(sizeVal as! AXValue) == .cgSize else {
            return nil
        }
        var size = CGSize.zero
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return size
    }

    private func setPosition(_ element: AXUIElement, x: CGFloat, y: CGFloat) {
        var point = CGPoint(x: x, y: y)
        let value: AXValue = AXValueCreate(.cgPoint, &point)!
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    private func findElementWithSubrole(root: AXUIElement, targetSubroles: [String]) -> AXUIElement? {
        var subroleRef: AnyObject?
        if AXUIElementCopyAttributeValue(root, kAXSubroleAttribute as CFString, &subroleRef) == .success {
            if let subrole: String = subroleRef as? String, targetSubroles.contains(subrole) {
                return root
            }
        }

        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children: [AXUIElement] = childrenRef as? [AXUIElement]
        else {
            return nil
        }

        for child: AXUIElement in children {
            if let found: AXUIElement = findElementWithSubrole(root: child, targetSubroles: targetSubroles) {
                return found
            }
        }
        return nil
    }
}

private func observerCallback(observer: AXObserver, element: AXUIElement, notification: CFString, context: UnsafeMutableRawPointer?) {
    guard let context = context else { return }
    let manager: NotificationPositionManager = Unmanaged<NotificationPositionManager>.fromOpaque(context).takeUnretainedValue()

    let notificationString: String = notification as String
    if notificationString == kAXWindowCreatedNotification as String {
        manager.moveNotification(element)
    }
}
