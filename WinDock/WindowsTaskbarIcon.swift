import SwiftUI
import AppKit

struct WindowsTaskbarIcon: View {
    let app: DockApp
    let isHovered: Bool
    let iconSize: CGFloat
    let appManager: AppManager

    @State private var isPressed = false
    @AppStorage("showLabels") private var showLabels = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Background with Windows 11 style
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundFill)
                    .frame(width: 48, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(borderColor, lineWidth: 1)
                    )
                    .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: 1)
                
                // App icon
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize * 0.7, height: iconSize * 0.7)
                }
                
                // Window count indicators (small dots at bottom)
                if app.windowCount > 1 {
                    HStack(spacing: 2) {
                        ForEach(0..<min(app.windowCount, 4), id: \.self) { _ in
                            Circle()
                                .fill(Color.primary.opacity(0.8))
                                .frame(width: 3, height: 3)
                        }
                        if app.windowCount > 4 {
                            Text("+")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.primary)
                        }
                    }
                    .offset(y: 16)
                }
            }
            
            // Running indicator (line at bottom)
            Rectangle()
                .fill(runningIndicatorColor)
                .frame(width: runningIndicatorWidth, height: 3)
                .cornerRadius(1.5)
                .padding(.top, 2)
                .opacity(app.isRunning ? 1.0 : 0.0)
            
            // App label (optional)
            if showLabels {
                Text(app.name)
                    .font(.system(size: 9))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 60)
                    .padding(.top, 2)
            }
        }
        .frame(width: 54, height: showLabels ? 72 : 54)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .contextMenu {
            AppContextMenuView(app: app, appManager: appManager)
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
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
        .help(toolTip)
    }

    private var backgroundFill: some ShapeStyle {
        if isPressed {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.3),
                        Color.accentColor.opacity(0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        if isHovered {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.15),
                        Color.accentColor.opacity(0.1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        if app.isRunning {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.08),
                        Color.accentColor.opacity(0.05)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(Color.clear)
    }
    
    private var borderColor: Color {
        if isHovered {
            return Color.accentColor.opacity(0.4)
        }
        if app.isRunning {
            return Color.accentColor.opacity(0.2)
        }
        return Color.clear
    }
    
    private var shadowColor: Color {
        if isPressed {
            return Color.black.opacity(0.1)
        }
        if isHovered {
            return Color.black.opacity(0.08)
        }
        return Color.clear
    }
    
    private var shadowRadius: CGFloat {
        if isPressed {
            return 1
        }
        if isHovered {
            return 3
        }
        return 0
    }
    
    private var runningIndicatorColor: Color {
        if app.runningApplication?.isActive == true {
            return Color.accentColor
        }
        return Color.accentColor.opacity(0.7)
    }
    
    private var runningIndicatorWidth: CGFloat {
        if app.runningApplication?.isActive == true {
            return 24
        }
        return 16
    }
    
    private var toolTip: String {
        var tooltip = app.name
        if app.isRunning {
            if app.windowCount > 0 {
                tooltip += " (\(app.windowCount) window\(app.windowCount == 1 ? "" : "s"))"
            }
            if app.runningApplication?.isActive == true {
                tooltip += " - Active"
            } else if app.runningApplication?.isHidden == true {
                tooltip += " - Hidden"
            }
        } else {
            tooltip += " - Click to launch"
        }
        return tooltip
    }
    
    private func handleTap() {
        // Windows 11 taskbar behavior
        if app.isRunning {
            if let runningApp = app.runningApplication {
                if runningApp.isActive {
                    // If app is active, minimize/hide or cycle windows
                    if app.windowCount > 1 {
                        appManager.cycleWindows(for: app)
                    } else {
                        appManager.hideApp(app)
                    }
                } else {
                    // If app is not active, bring it to front
                    appManager.activateApp(app)
                }
            }
        } else {
            // Launch the app
            appManager.activateApp(app)
        }
    }
}
