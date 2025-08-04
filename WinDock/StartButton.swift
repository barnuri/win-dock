import SwiftUI
import AppKit

struct StartButton: View {
    @State private var showStartMenu = false
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: { showStartMenu.toggle() }) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundFill)
                    .frame(width: 48, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isHovered ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                            .animation(.easeInOut(duration: 0.15), value: isHovered)
                    )
                
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .medium))
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
        .help("Start Menu")
        .popover(isPresented: $showStartMenu, arrowEdge: .top) {
            StartMenuView()
        }
    }
    
    private var backgroundFill: some ShapeStyle {
        if isPressed {
            return AnyShapeStyle(Color.accentColor.opacity(0.2))
        }
        if isHovered {
            return AnyShapeStyle(Color.accentColor.opacity(0.15))
        }
        if showStartMenu {
            return AnyShapeStyle(Color.accentColor.opacity(0.1))
        }
        return AnyShapeStyle(Color.clear)
    }
}

#Preview {
    StartButton()
        .preferredColorScheme(.light)
}
