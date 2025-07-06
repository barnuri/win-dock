import AppKit

final class TaskbarWindowConfigurator {
    static let shared = TaskbarWindowConfigurator()
    private init() {}

    func configure() {
        guard let window = NSApplication.shared.windows.first else { return }

        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovable = false

        position(window: window)
    }

    private func position(window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let height: CGFloat = 48
        let y: CGFloat = screen.frame.minY   // bottom of the screen
        let frame = CGRect(x: 0,
                           y: y,
                           width: screen.frame.width,
                           height: height)
        window.setFrame(frame, display: true)
    }
}
