import SwiftUI
import AppKit

struct WindowsTaskbarIcon: View {
    let app: DockApp
    let isHovered: Bool
    let iconSize: CGFloat
    let appManager: AppManager

    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(backgroundFill)
                    .frame(width: 48, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(isHovered ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
                    )
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                }
                if app.windowCount > 1 {
                    HStack(spacing: 2) {
                        ForEach(0..<min(app.windowCount, 3), id: \ .self) { _ in
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 4, height: 2)
                                .cornerRadius(1)
                        }
                    }
                    .offset(y: 18)
                }
            }
            Rectangle()
                .fill(app.isRunning ? (isHovered ? Color.accentColor : Color.accentColor.opacity(0.7)) : Color.clear)
                .frame(width: 32, height: app.isRunning ? 4 : 2)
                .cornerRadius(2)
                .padding(.top, 4)
        }
        .frame(width: 54, height: 54)
        .contentShape(Rectangle())
        .onTapGesture {
            for currentApp in appManager.dockApps.filter({ $0.bundleIdentifier == app.bundleIdentifier }) {
                if currentApp.isRunning && currentApp.runningApplication?.isActive == true {
                    appManager.hideApp(currentApp)
                } else {
                    appManager.activateApp(currentApp)
                }
            }
        }
        .contextMenu {
            AppContextMenuView(app: app, appManager: appManager)
        }
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { _ in
                if app.isRunning {
                    appManager.launchNewInstance(app)
                }
            }
        )
    }

    private var backgroundFill: some ShapeStyle {
        if isPressed {
            return AnyShapeStyle(Color.accentColor.opacity(0.18))
        }
        if isHovered {
            return AnyShapeStyle(Color.accentColor.opacity(0.13))
        }
        if app.isRunning {
            return AnyShapeStyle(Color.accentColor.opacity(0.08))
        }
        return AnyShapeStyle(Color.clear)
    }
}
