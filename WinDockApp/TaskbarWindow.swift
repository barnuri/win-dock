import SwiftUI

struct TaskbarWindow: View {
    @EnvironmentObject var monitor: RunningAppMonitor

    var body: some View {
        HStack(spacing: 12) {
            ForEach(monitor.runningApps, id: \.bundleIdentifier) { app in
                AppIconView(app: app)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: 48)
        .background(.ultraThinMaterial)
        .onAppear {
            TaskbarWindowConfigurator.shared.configure()
        }
    }
}
