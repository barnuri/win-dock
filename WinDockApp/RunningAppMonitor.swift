import Foundation
import AppKit
import Combine

final class RunningAppMonitor: ObservableObject {
    static let shared = RunningAppMonitor()

    @Published var runningApps: [NSRunningApplication] = []

    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {
        refresh()
        let nc = NSWorkspace.shared.notificationCenter
        let opts: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification
        ]
        workspaceObservers = opts.map { name in
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { nc.removeObserver($0) }
    }
}
