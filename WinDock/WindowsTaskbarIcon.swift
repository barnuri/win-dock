import SwiftUI
import AppKit

struct WindowsTaskbarIcon: View {
    let app: DockApp
    let isHovered: Bool
    let iconSize: CGFloat
    let onTap: () -> Void
    let onRightClick: (CGPoint) -> Void
    let appManager: AppManager
    
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundFill)
                    .frame(width: 40, height: 40)
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
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
                    .offset(y: 23)
                }
            }
            if app.isRunning {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: isHovered ? 30 : (app.windowCount > 0 ? 20 : 6), height: 3)
                    .cornerRadius(1.5)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
                    .padding(.top, 2)
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 30, height: 3)
                    .padding(.top, 2)
            }
        }
        .frame(width: 40, height: 50)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            AppContextMenuView(app: app, appManager: appManager)
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
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
            return AnyShapeStyle(Color.white.opacity(0.25))
        } else if isHovered {
            return AnyShapeStyle(Color.white.opacity(0.15))
        } else if app.isRunning {
            return AnyShapeStyle(Color.white.opacity(0.08))
        } else {
            return AnyShapeStyle(Color.clear)
        }
    }
}
