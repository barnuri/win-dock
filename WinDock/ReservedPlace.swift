import SwiftUI
import AppKit

/**
 * ReservedPlace creates a non-interactive transparent window that reserves
 * screen space based on dock position and size settings.
 */
class ReservedPlaceWindow: NSWindow {
    // Get settings from UserDefaults
    @AppStorage("dockPosition") private var dockPosition: DockPosition = .bottom
    @AppStorage("dockSize") private var dockSize: DockSize = .medium
    
    // Notification observer
    private var settingsObserver: NSObjectProtocol?
    
    convenience init() {
        // Initial setup with dummy frame, will be updated in updatePosition
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        setup()
    }
    
    private func setup() {
        // Set up window properties for a "reserved space" window
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        
        // Initial position update
        updatePosition()
        
        // Observe settings changes to update position and size
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePosition()
        }
        
        // Also observe screen parameter changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        // Listen for position change notifications from the main dock
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dockPositionChanged),
            name: NSNotification.Name("WinDockPositionChanged"),
            object: nil
        )
        
        // Make window visible
        makeKeyAndOrderFront(nil)
    }
    
    @objc private func screenParametersDidChange() {
        updatePosition()
    }
    
    @objc private func dockPositionChanged() {
        // The dock has changed position - update our position accordingly
        updatePosition()
    }
    
    private func updatePosition() {
        guard let screen = NSScreen.main else { return }
        
        // Get padding values from UserDefaults
        let paddingTop = CGFloat(UserDefaults.standard.double(forKey: "paddingTop"))
        let paddingBottom = CGFloat(UserDefaults.standard.double(forKey: "paddingBottom"))
        let paddingLeft = CGFloat(UserDefaults.standard.double(forKey: "paddingLeft"))
        let paddingRight = CGFloat(UserDefaults.standard.double(forKey: "paddingRight"))
        
        // Calculate dock height based on selected size
        let dockHeight: CGFloat = getDockHeight()
        
        // Set window frame based on dock position and screen size
        let screenFrame = screen.frame
        var windowFrame = NSRect.zero
        
        switch dockPosition {
        case .bottom:
            windowFrame = NSRect(
                x: screenFrame.minX + paddingLeft,
                y: screenFrame.minY + paddingBottom,
                width: screenFrame.width - paddingLeft - paddingRight,
                height: dockHeight
            )
        case .top:
            windowFrame = NSRect(
                x: screenFrame.minX + paddingLeft,
                y: screenFrame.maxY - dockHeight - paddingTop,
                width: screenFrame.width - paddingLeft - paddingRight,
                height: dockHeight
            )
        case .left:
            windowFrame = NSRect(
                x: screenFrame.minX + paddingLeft,
                y: screenFrame.minY + paddingBottom,
                width: dockHeight,
                height: screenFrame.height - paddingTop - paddingBottom
            )
        case .right:
            windowFrame = NSRect(
                x: screenFrame.maxX - dockHeight - paddingRight,
                y: screenFrame.minY + paddingBottom,
                width: dockHeight,
                height: screenFrame.height - paddingTop - paddingBottom
            )
        }
        
        // Update window frame
        setFrame(windowFrame, display: true)
    }
    
    private func getDockHeight() -> CGFloat {
        switch dockSize {
        case .small: return 48
        case .medium: return 56
        case .large: return 64
        }
    }
    
    deinit {
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        NotificationCenter.default.removeObserver(self)
    }
}

struct ReservedPlace: View {
    @State private var window: ReservedPlaceWindow?
    
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                createWindow()
            }
            .onDisappear {
                window?.close()
                window = nil
            }
    }
    
    private func createWindow() {
        let window = ReservedPlaceWindow()
        self.window = window
    }
}

#Preview {
    ReservedPlace()
}
