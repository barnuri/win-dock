import SwiftUI

// Function to calculate dock frame based on position and screen
// Moved from SettingsView.swift to make it globally accessible
func dockFrame(for position: DockPosition, screen: NSScreen) -> NSRect {
    let visibleFrame = screen.visibleFrame
    let dockHeight: CGFloat = getDockHeight()
    
    // Get padding values from UserDefaults - simplified to horizontal and vertical
    let paddingVertical = CGFloat(UserDefaults.standard.double(forKey: "paddingVertical"))
    let paddingHorizontal = CGFloat(UserDefaults.standard.double(forKey: "paddingHorizontal"))
    
    switch position {
    case .bottom:
        // Use full screen frame for bottom to avoid safe area
        return NSRect(
            x: visibleFrame.minX + paddingHorizontal,
            y: visibleFrame.minY + paddingVertical,
            width: visibleFrame.width - (paddingHorizontal * 2),
            height: dockHeight
        )
    case .top:
        return NSRect(
            x: visibleFrame.minX + paddingHorizontal,
            y: visibleFrame.maxY - dockHeight - paddingVertical,
            width: visibleFrame.width - (paddingHorizontal * 2),
            height: dockHeight
        )
    case .left:
        return NSRect(
            x: visibleFrame.minX + paddingHorizontal,
            y: visibleFrame.minY + paddingVertical,
            width: dockHeight,
            height: visibleFrame.height - (paddingVertical * 2)
        )
    case .right:
        return NSRect(
            x: visibleFrame.maxX - dockHeight - paddingHorizontal,
            y: visibleFrame.minY + paddingVertical,
            width: dockHeight,
            height: visibleFrame.height - (paddingVertical * 2)
        )
    }
}

func getDockHeight() -> CGFloat {
    let dockSizeString = UserDefaults.standard.string(forKey: "dockSize") ?? "medium"
    let dockSize = DockSize(rawValue: dockSizeString) ?? .medium
    return dockSize.height
}
