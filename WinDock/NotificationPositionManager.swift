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
        debugLog("NotificationPositionManager initialized - enabled: \(isEnabled), position: \(currentPosition.displayName)")
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

        // Safe to use passUnretained since NotificationPositionManager is a singleton that never deallocates
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

        // Use weak self to prevent retain cycle
        widgetMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForWidgetChanges()
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
    
    public func stop() {
        stopObserver()
        debugLog("NotificationPositionManager stopped")
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
        var visitedElements = Set<String>()
        return findElementWithWidgetIdentifier(root: app, visitedElements: &visitedElements, depth: 0) != nil
    }

    private func findElementWithWidgetIdentifier(root: AXUIElement, visitedElements: inout Set<String>, depth: Int) -> AXUIElement? {
        // Prevent infinite recursion by limiting depth and tracking visited elements
        guard depth < 50 else {
            debugLog("Maximum recursion depth reached in findElementWithWidgetIdentifier")
            return nil
        }
        
        // Create a unique identifier for this element to detect cycles
        let elementHash = String(describing: root)
        if visitedElements.contains(elementHash) {
            debugLog("Cycle detected in accessibility tree - skipping already visited element")
            return nil
        }
        visitedElements.insert(elementHash)
        
        // Check if this element has the widget identifier
        if let identifier: String = getWindowIdentifier(root), identifier.hasPrefix("widget-local") {
            return root
        }

        // Get children with error handling
        var childrenRef: AnyObject?
        let childrenResult = AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &childrenRef)
        guard childrenResult == .success,
              let children: [AXUIElement] = childrenRef as? [AXUIElement] else {
            if childrenResult != .noValue && childrenResult != .attributeUnsupported {
                debugLog("Failed to get children for accessibility element: \(childrenResult)")
            }
            return nil
        }

        // Recursively search children
        for child: AXUIElement in children {
            if let found: AXUIElement = findElementWithWidgetIdentifier(root: child, visitedElements: &visitedElements, depth: depth + 1) {
                return found
            }
        }
        return nil
    }
    
    private func getWindowIdentifier(_ element: AXUIElement) -> String? {
        var identifierRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierRef)
        
        guard result == .success else {
            // Don't log for common cases where identifier is not available
            if result != .noValue && result != .attributeUnsupported {
                debugLog("Failed to get window identifier: \(result)")
            }
            return nil
        }
        
        return identifierRef as? String
    }

    private func getPosition(of element: AXUIElement) -> CGPoint? {
        var positionValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        guard let posVal: AnyObject = positionValue else {
            return nil
        }
        
        // Safely check type before casting
        guard CFGetTypeID(posVal) == AXValueGetTypeID(),
              AXValueGetType(posVal as! AXValue) == .cgPoint else {
            return nil
        }
        
        var position = CGPoint.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
        return position
    }

    private func getSize(of element: AXUIElement) -> CGSize? {
        var sizeValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        guard let sizeVal: AnyObject = sizeValue else {
            return nil
        }
        
        // Safely check type before casting
        guard CFGetTypeID(sizeVal) == AXValueGetTypeID(),
              AXValueGetType(sizeVal as! AXValue) == .cgSize else {
            return nil
        }
        
        var size = CGSize.zero
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return size
    }

    private func setPosition(_ element: AXUIElement, x: CGFloat, y: CGFloat) {
        var point = CGPoint(x: x, y: y)
        guard let value = AXValueCreate(.cgPoint, &point) else {
            debugLog("Failed to create AXValue for position")
            return
        }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    private func findElementWithSubrole(root: AXUIElement, targetSubroles: [String]) -> AXUIElement? {
        return findElementWithSubrole(root: root, targetSubroles: targetSubroles, depth: 0)
    }
    
    private func findElementWithSubrole(root: AXUIElement, targetSubroles: [String], depth: Int) -> AXUIElement? {
        // Prevent infinite recursion by limiting depth
        guard depth < 20 else {
            debugLog("Maximum recursion depth reached in findElementWithSubrole")
            return nil
        }
        
        var subroleRef: AnyObject?
        if AXUIElementCopyAttributeValue(root, kAXSubroleAttribute as CFString, &subroleRef) == .success {
            if let subrole: String = subroleRef as? String, targetSubroles.contains(subrole) {
                return root
            }
        }

        var childrenRef: AnyObject?
        let childrenResult = AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &childrenRef)
        guard childrenResult == .success,
              let children: [AXUIElement] = childrenRef as? [AXUIElement]
        else {
            if childrenResult != .noValue && childrenResult != .attributeUnsupported {
                debugLog("Failed to get children in findElementWithSubrole: \(childrenResult)")
            }
            return nil
        }

        for child: AXUIElement in children {
            if let found: AXUIElement = findElementWithSubrole(root: child, targetSubroles: targetSubroles, depth: depth + 1) {
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
