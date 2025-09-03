import AppKit
import SwiftUI

// Helper class to store weak references in collections
class WeakRef<T: AnyObject> {
    weak var value: T?
    
    init(_ value: T) {
        self.value = value
    }
}

class DockVisibilityManager: ObservableObject {
    static let shared = DockVisibilityManager()
    
    @Published private(set) var isVisible = true
    @Published private(set) var isManuallyHidden = false
    private var dockWindows: [WeakRef<DockWindow>] = []
    
    private init() {}
    
    func addDockWindow(_ window: DockWindow) {
        // Remove any existing references to the same window
        dockWindows.removeAll { $0.value == nil || $0.value === window }
        // Add the new window
        dockWindows.append(WeakRef(window))
    }
    
    func removeDockWindow(_ window: DockWindow) {
        dockWindows.removeAll { $0.value == nil || $0.value === window }
    }
    
    private func cleanupWeakReferences() {
        dockWindows.removeAll { $0.value == nil }
    }
    
    func toggleVisibility() {
        if isVisible && !isManuallyHidden {
            hideDock()
        } else {
            showDock()
        }
    }
    
    func hideDock() {
        cleanupWeakReferences()
        guard isVisible, !dockWindows.isEmpty else { return }
        
        isVisible = false
        isManuallyHidden = true
        
        for windowRef in dockWindows {
            guard let window = windowRef.value else { continue }
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 0.0
            } completionHandler: {
                // Don't order out the window to keep it accessible for fullscreen detection
            }
        }
        
        AppLogger.shared.info("All dock windows manually hidden via DockVisibilityManager")
    }
    
    func showDock() {
        cleanupWeakReferences()
        guard (!isVisible || isManuallyHidden), !dockWindows.isEmpty else { return }
        
        isVisible = true
        isManuallyHidden = false
        
        for windowRef in dockWindows {
            guard let window = windowRef.value else { continue }
            
            // Bring window back on screen first
            window.orderFront(nil)
            window.alphaValue = 0.0 // Start from transparent
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 1.0
            }
        }
        
        AppLogger.shared.info("All dock windows manually shown via DockVisibilityManager")
    }
    
    func hideForFullscreen() {
        cleanupWeakReferences()
        guard isVisible && !isManuallyHidden, !dockWindows.isEmpty else { return }
        
        isVisible = false
        // Don't set isManuallyHidden = true for fullscreen auto-hide
        
        for windowRef in dockWindows {
            guard let window = windowRef.value else { continue }
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 0.0
            }
        }
        
        AppLogger.shared.info("All dock windows hidden for fullscreen")
    }
    
    func showAfterFullscreen() {
        cleanupWeakReferences()
        guard !isVisible && !isManuallyHidden, !dockWindows.isEmpty else { return }
        
        isVisible = true
        
        for windowRef in dockWindows {
            guard let window = windowRef.value else { continue }
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 1.0
            }
        }
        
        AppLogger.shared.info("All dock windows shown after fullscreen")
    }
    
    var visibilityDisplayName: String {
        return "Hide/Show"
    }
}