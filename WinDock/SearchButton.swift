import SwiftUI
import AppKit

struct SearchButton: View {
    @State private var isHovered = false
    @State private var isPressed = false
    @AppStorage("searchAppChoice") private var searchAppChoice: SearchAppChoice = .spotlight
    
    var body: some View {
        Button(action: openSearchApp) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundFill)
                    .frame(width: 48, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isHovered ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
        .help("Search (\(searchAppChoice.displayName))")
    }
    
    private var backgroundFill: some ShapeStyle {
        if isPressed {
            return AnyShapeStyle(Color.accentColor.opacity(0.2))
        }
        if isHovered {
            return AnyShapeStyle(Color.accentColor.opacity(0.15))
        }
        return AnyShapeStyle(Color.clear)
    }
    
    private func openSearchApp() {
        switch searchAppChoice {
        case .spotlight:
            openSpotlight()
        case .raycast:
            openRaycast()
        case .alfred:
            openAlfred()
        }
    }
    
    private func openSpotlight() {
        if let spotlightURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Spotlight") {
            NSWorkspace.shared.open(spotlightURL)
        } else {
            // Fallback to AppleScript if direct launch fails
            let script = "tell application \"System Events\" to keystroke space using {command down}"
            executeAppleScript(script)
        }
    }
    
    private func openRaycast() {
        if let raycastURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.raycast.macos") {
            NSWorkspace.shared.open(raycastURL)
        } else {
            // Fallback to Spotlight if Raycast is not installed
            openSpotlight()
        }
    }
    
    private func openAlfred() {
        if let alfredURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.runningwithcrayons.Alfred") {
            NSWorkspace.shared.open(alfredURL)
        } else {
            // Fallback to Spotlight if Alfred is not installed
            openSpotlight()
        }
    }
    
    private func executeAppleScript(_ script: String) {
        guard let appleScript = NSAppleScript(source: script) else { return }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error = error {
            AppLogger.shared.error("AppleScript error: \(error)")
        }
    }
}

#Preview {
    SearchButton()
        .preferredColorScheme(.light)
}
